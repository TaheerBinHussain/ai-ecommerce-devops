# AI-assisted incident analysis

```
logs (files | stdin | Elasticsearch | Jenkins failure bundle)
      ▼
Rule engine  - 14 known failure signatures (rules.py) + HTTP statistics (5xx rate, 404s, slow requests)
      ▼        → classification, severity, possible root cause, investigation, remediation
Optional LLM - --llm sends the condensed findings + sample lines to Claude (claude-opus-5-5),
      ▼        which returns schema-validated JSON: correlated root cause, confidence, evidence, steps, prevention
Report       - Markdown (default) or JSON; --fail-on <severity> turns it into a CI gate
```

```bash
python3 analyze.py samples/db-timeout.log
kubectl -n ecommerce logs -l app.kubernetes.io/instance=nexvion --all-containers | python3 analyze.py -
python3 analyze.py --es-url http://localhost:9200 --minutes 30
pip install -r requirements.txt && export ANTHROPIC_API_KEY=...   # optional
python3 analyze.py samples/db-timeout.log --llm --output report.md
python3 -m unittest discover -s tests -v
```

Classified incident types: database connectivity, OOMKilled, CrashLoopBackOff, image pull failures, nginx
config errors, disk full, probe failures, upstream timeouts/unavailability, DNS, TLS, permissions, rate
limiting, missing assets, 5xx spikes, 404 spikes, slow requests.

Design choices:
- The rule engine works offline and deterministically, so the pipeline never depends on an external API.
- Only summarised findings and a few sample lines are sent to the LLM, never whole log files.
- The LLM response is constrained by a JSON schema, so the report format is reliable.
- Any API problem (no key, rate limit, network) falls back to the rule-engine report.
