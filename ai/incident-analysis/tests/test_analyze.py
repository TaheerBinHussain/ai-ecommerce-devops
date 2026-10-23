import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import analyze  # noqa: E402

SAMPLES = HERE / "samples"


def run(name):
    return analyze.analyze((SAMPLES / name).read_text().splitlines())


class AnalyzerTests(unittest.TestCase):
    def test_database_timeout_is_critical_and_top_finding(self):
        report = run("db-timeout.log")
        self.assertEqual(report["severity"], "critical")
        self.assertEqual(report["findings"][0]["id"], "db_connection_timeout")
        ids = {f["id"] for f in report["findings"]}
        self.assertIn("probe_failure", ids)
        self.assertIn("http_5xx_spike", ids)

    def test_http_statistics(self):
        stats = run("db-timeout.log")["http_stats"]
        self.assertEqual(stats["requests"], 4)
        self.assertEqual(stats["error_rate_5xx_pct"], 75.0)

    def test_crashloop_from_bad_nginx_config(self):
        ids = [f["id"] for f in run("k8s-crashloop.log")["findings"]]
        self.assertIn("nginx_config", ids)
        self.assertIn("crash_loop", ids)

    def test_healthy_traffic_has_no_findings(self):
        report = run("healthy-traffic.log")
        self.assertEqual(report["findings"], [])
        self.assertEqual(report["severity"], "info")

    def test_fail_on_gate_exit_code(self):
        code = analyze.main([str(SAMPLES / "db-timeout.log"), "--format", "json", "--fail-on", "high"])
        self.assertEqual(code, 2)
        code = analyze.main([str(SAMPLES / "healthy-traffic.log"), "--fail-on", "high"])
        self.assertEqual(code, 0)

    def test_markdown_report_contains_guidance(self):
        md = analyze.to_markdown(run("db-timeout.log"))
        self.assertIn("Suggested investigation", md)
        self.assertIn("Database connectivity", md)


if __name__ == "__main__":
    unittest.main()
