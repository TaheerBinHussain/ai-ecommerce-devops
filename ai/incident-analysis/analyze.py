#!/usr/bin/env python3
"""AI-assisted incident analysis for the NEXVION DevOps platform.

Reads application / Kubernetes / Nginx logs (files, stdin or Elasticsearch),
classifies errors, rates incident severity, identifies the probable root cause,
and suggests investigation and remediation steps.

Two layers:
  1. Rule engine (always on, offline): known failure signatures + HTTP statistics.
  2. LLM enrichment (optional, --llm): sends the condensed findings and sample
     error lines to Claude, which returns a structured root-cause analysis.

Usage:
  analyze.py app.log k8s-events.log            # files
  kubectl logs deploy/x | analyze.py -          # stdin
  analyze.py --es-url http://localhost:9200     # last 15 min from Elasticsearch
  analyze.py app.log --llm --format json --output report.json
Exit code: 0 normally; 2 if --fail-on is set and the severity reaches it.
"""
import argparse
import json
import os
import re
import sys
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rules import RULES, SEVERITY_ORDER  # noqa: E402

MAX_SAMPLES_PER_RULE = 3
ERROR_HINT = re.compile(r"error|fail|fatal|panic|exception|refused|timed? ?out|denied|crit|emerg", re.IGNORECASE)


# ---------------------------------------------------------------- input
def read_sources(paths):
    lines = []
    for p in paths:
        if p == "-":
            lines.extend(sys.stdin.read().splitlines())
        else:
            lines.extend(Path(p).read_text(errors="replace").splitlines())
    return lines


def read_elasticsearch(url, index, minutes):
    """Fetch recent warning/error documents produced by the Logstash pipeline."""
    query = {
        "size": 2000,
        "sort": [{"@timestamp": "desc"}],
        "query": {"bool": {"filter": [{"range": {"@timestamp": {"gte": f"now-{minutes}m"}}}]}},
    }
    req = urllib.request.Request(
        f"{url.rstrip('/')}/{index}/_search",
        data=json.dumps(query).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        hits = json.load(resp)["hits"]["hits"]
    return [h["_source"].get("message", json.dumps(h["_source"])) for h in hits]


# ---------------------------------------------------------------- analysis
def _http_record(line):
    """Return the parsed Nginx JSON access-log record in a line, if any."""
    start = line.find("{")
    if start == -1 or '"status"' not in line:
        return None
    try:
        rec = json.loads(line[start:])
    except ValueError:
        return None
    return rec if isinstance(rec, dict) and "status" in rec else None


def http_findings(records):
    findings = []
    total = len(records)
    if not total:
        return findings, {}
    statuses = Counter(int(r["status"]) // 100 * 100 for r in records)
    errors_5xx = sum(1 for r in records if int(r["status"]) >= 500)
    not_found = [r for r in records if int(r["status"]) == 404]
    slow = [r for r in records if float(r.get("request_time", 0) or 0) > 1.0]
    stats = {
        "requests": total,
        "status_classes": {f"{k // 100}xx": v for k, v in sorted(statuses.items())},
        "error_rate_5xx_pct": round(errors_5xx / total * 100, 2),
        "not_found": len(not_found),
        "slow_requests_over_1s": len(slow),
    }

    rate = stats["error_rate_5xx_pct"]
    if errors_5xx and rate >= 1:
        findings.append({
            "id": "http_5xx_spike", "category": "Server errors",
            "severity": "critical" if rate >= 10 else "high",
            "count": errors_5xx,
            "root_cause": f"{rate}% of requests returned 5xx - the service is failing for real users.",
            "investigation": ["Correlate the start time with the latest deployment (helm history)",
                              "Check pod health and restarts (kubectl get pods)",
                              "Filter Kibana for http.status >= 500 and look at the URIs affected"],
            "remediation": ["helm rollback to the last healthy revision if it started after a release"],
            "samples": [json.dumps(r) for r in records if int(r["status"]) >= 500][:MAX_SAMPLES_PER_RULE],
        })
    if len(not_found) >= 5 and len(not_found) / total >= 0.05:
        top = Counter(r.get("uri", "?") for r in not_found).most_common(3)
        findings.append({
            "id": "http_404_spike", "category": "Broken content", "severity": "medium",
            "count": len(not_found),
            "root_cause": "Many requests hit missing pages/assets: " + ", ".join(f"{u} ({c})" for u, c in top),
            "investigation": ["Check whether these paths existed in the previous release",
                              "Run the application link test (npm test)"],
            "remediation": ["Restore or redirect the missing paths"],
            "samples": [json.dumps(r) for r in not_found][:MAX_SAMPLES_PER_RULE],
        })
    if len(slow) >= 3:
        findings.append({
            "id": "slow_requests", "category": "Performance", "severity": "medium",
            "count": len(slow),
            "root_cause": f"{len(slow)} requests took longer than 1s.",
            "investigation": ["Check CPU throttling / saturation in Grafana", "Check node resource pressure"],
            "remediation": ["Scale out (HPA) or raise CPU limits"],
            "samples": [json.dumps(r) for r in slow][:MAX_SAMPLES_PER_RULE],
        })
    return findings, stats


def analyze(lines):
    records, other = [], []
    for line in lines:
        rec = _http_record(line)
        (records if rec else other).append(rec or line)

    findings = []
    matched_lines = set()
    for rule in RULES:
        hits = [(i, l) for i, l in enumerate(other) if rule.pattern.search(l)]
        if not hits:
            continue
        matched_lines.update(i for i, _ in hits)
        findings.append({
            "id": rule.id, "category": rule.category, "severity": rule.severity,
            "count": len(hits), "root_cause": rule.root_cause,
            "investigation": rule.investigation, "remediation": rule.remediation,
            "samples": [l.strip()[:400] for _, l in hits[:MAX_SAMPLES_PER_RULE]],
        })

    http, stats = http_findings(records)
    findings.extend(http)

    unclassified = [l.strip()[:400] for i, l in enumerate(other) if i not in matched_lines and ERROR_HINT.search(l)]
    findings.sort(key=lambda f: (SEVERITY_ORDER[f["severity"]], f["count"]), reverse=True)
    severity = findings[0]["severity"] if findings else ("low" if unclassified else "info")

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "lines_analyzed": len(lines),
        "severity": severity,
        "summary": _summary(findings, severity),
        "http_stats": stats,
        "findings": findings,
        "unclassified_errors": unclassified[:20],
        "ai_analysis": None,
    }


def _summary(findings, severity):
    if not findings:
        return "No known failure signatures detected."
    top = findings[0]
    others = len(findings) - 1
    extra = f" (+{others} related finding{'s' if others != 1 else ''})" if others else ""
    return f"{severity.upper()}: {top['category']} - {top['count']} matching event(s){extra}."


# ---------------------------------------------------------------- LLM enrichment
AI_SCHEMA = {
    "type": "object",
    "properties": {
        "incident_title": {"type": "string"},
        "severity": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
        "probable_root_cause": {"type": "string"},
        "confidence": {"type": "string", "enum": ["low", "medium", "high"]},
        "evidence": {"type": "array", "items": {"type": "string"}},
        "investigation_steps": {"type": "array", "items": {"type": "string"}},
        "remediation_steps": {"type": "array", "items": {"type": "string"}},
        "prevention": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["incident_title", "severity", "probable_root_cause", "confidence",
                 "evidence", "investigation_steps", "remediation_steps", "prevention"],
    "additionalProperties": False,
}

SYSTEM_PROMPT = (
    "You are an SRE assistant for an e-commerce platform: a static storefront served by non-root Nginx "
    "containers, deployed with Helm on Kubernetes (kind locally, k3s on AWS EC2), images in ECR, CI/CD in "
    "Jenkins, metrics in Prometheus/Grafana and logs in ELK. You receive findings from a rule-based log "
    "analyzer plus sample log lines. Correlate them into one incident assessment. Base every claim on the "
    "evidence given; if the evidence is thin, say so and lower the confidence. Give concrete commands "
    "(kubectl, helm, docker, curl) where they help."
)


def ai_enrich(report, model):
    """Ask Claude for a correlated root-cause analysis. Returns None if unavailable."""
    try:
        import anthropic
    except ImportError:
        print("[ai] 'anthropic' package not installed (pip install anthropic) - using rule engine only", file=sys.stderr)
        return None

    payload = {k: report[k] for k in ("severity", "summary", "http_stats", "findings", "unclassified_errors")}
    client = anthropic.Anthropic()
    try:
        response = client.beta.messages.create(
            model=model,
            max_tokens=16000,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": "Analyze this incident data:\n" + json.dumps(payload, indent=2)}],
            output_config={"effort": "medium", "format": {"type": "json_schema", "schema": AI_SCHEMA}},
            # Re-run on another model automatically if a safety classifier declines the request
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
    except (anthropic.AuthenticationError, TypeError):
        # TypeError: the SDK found no credentials at all (no ANTHROPIC_API_KEY / profile)
        print("[ai] no valid Anthropic credentials (set ANTHROPIC_API_KEY) - using rule engine only", file=sys.stderr)
        return None
    except anthropic.RateLimitError:
        print("[ai] rate limited - using rule engine only", file=sys.stderr)
        return None
    except anthropic.APIStatusError as exc:
        print(f"[ai] API error {exc.status_code} - using rule engine only", file=sys.stderr)
        return None
    except anthropic.APIConnectionError:
        print("[ai] cannot reach the Anthropic API - using rule engine only", file=sys.stderr)
        return None

    if response.stop_reason == "refusal":
        print("[ai] request declined - using rule engine only", file=sys.stderr)
        return None
    text = next((b.text for b in response.content if b.type == "text"), None)
    if not text:
        return None
    result = json.loads(text)
    result["model"] = response.model
    return result


# ---------------------------------------------------------------- output
def to_markdown(report):
    out = [
        "# Incident Analysis Report",
        "",
        f"- **Generated:** {report['generated_at']}",
        f"- **Lines analysed:** {report['lines_analyzed']}",
        f"- **Severity:** `{report['severity'].upper()}`",
        f"- **Summary:** {report['summary']}",
        "",
    ]
    if report["http_stats"]:
        s = report["http_stats"]
        out += ["## Traffic", "",
                f"Requests: {s['requests']} | status classes: {s['status_classes']} | "
                f"5xx rate: {s['error_rate_5xx_pct']}% | 404s: {s['not_found']} | slow (>1s): {s['slow_requests_over_1s']}", ""]

    ai = report.get("ai_analysis")
    if ai:
        out += [f"## AI root-cause analysis ({ai.get('model', 'Claude')})", "",
                f"**{ai['incident_title']}** - severity `{ai['severity']}`, confidence `{ai['confidence']}`", "",
                f"**Probable root cause:** {ai['probable_root_cause']}", ""]
        for title, key in (("Evidence", "evidence"), ("Investigation", "investigation_steps"),
                           ("Remediation", "remediation_steps"), ("Prevention", "prevention")):
            out += [f"**{title}**", ""] + [f"{i}. {x}" for i, x in enumerate(ai[key], 1)] + [""]

    out += ["## Findings", ""]
    if not report["findings"]:
        out += ["No known failure signatures detected.", ""]
    for n, f in enumerate(report["findings"], 1):
        out += [f"### {n}. {f['category']} - `{f['severity']}` ({f['count']} events)", "",
                f"**Possible cause:** {f['root_cause']}", "", "**Suggested investigation**", ""]
        out += [f"- {x}" for x in f["investigation"]] + ["", "**Suggested remediation**", ""]
        out += [f"- {x}" for x in f["remediation"]] + ["", "**Sample log lines**", "", "```"]
        out += f["samples"] + ["```", ""]
    if report["unclassified_errors"]:
        out += ["## Unclassified error lines", "", "```"] + report["unclassified_errors"] + ["```", ""]
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sources", nargs="*", help="log files, or - for stdin")
    ap.add_argument("--es-url", help="read recent logs from Elasticsearch instead of files")
    ap.add_argument("--es-index", default="nexvion-logs-*")
    ap.add_argument("--minutes", type=int, default=15, help="time window for --es-url")
    ap.add_argument("--llm", action="store_true", help="enrich the analysis with Claude (needs ANTHROPIC_API_KEY)")
    ap.add_argument("--model", default=os.environ.get("INCIDENT_AI_MODEL", "claude-opus-5-5"))
    ap.add_argument("--format", choices=["markdown", "json"], default="markdown")
    ap.add_argument("--output", help="write the report to this file as well as stdout")
    ap.add_argument("--fail-on", choices=["low", "medium", "high", "critical"],
                    help="exit with code 2 when severity is at or above this level (CI gate)")
    args = ap.parse_args(argv)

    if args.es_url:
        lines = read_elasticsearch(args.es_url, args.es_index, args.minutes)
    elif args.sources:
        lines = read_sources(args.sources)
    else:
        ap.error("give log files, '-' for stdin, or --es-url")

    report = analyze(lines)
    if args.llm and report["findings"] + report["unclassified_errors"]:
        report["ai_analysis"] = ai_enrich(report, args.model)

    text = json.dumps(report, indent=2) if args.format == "json" else to_markdown(report)
    print(text)
    if args.output:
        Path(args.output).write_text(text + "\n")
        print(f"\n[report written to {args.output}]", file=sys.stderr)

    if args.fail_on and SEVERITY_ORDER[report["severity"]] >= SEVERITY_ORDER[args.fail_on]:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
