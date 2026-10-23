# Centralized logging (ELK)

```
nexvion container (JSON access log on stdout)
      │  docker json-file log
      ▼
Filebeat (docker autodiscover, label co.elastic.logs/enabled=true)
      ▼
Logstash (parse JSON / grok error log, derive log_level)
      ▼
Elasticsearch index nexvion-logs-YYYY.MM.DD
      ▼
Kibana (data view "nexvion-logs-*")  ──►  AI incident analysis (ai/incident-analysis)
```

Start it with `./scripts/deploy.sh compose --with-logging` and then run
`logging/elk/kibana-setup.sh` to create the data view.

Useful Kibana (KQL) queries:

| Question | Query |
|---|---|
| All server errors | `http.status >= 500` |
| Missing pages / broken links | `http.status : 404` |
| Slow requests | `http.request_time > 1` |
| Checkout traffic | `http.uri : "/payment.html*"` |
| Nginx error log only | `tags : "error_log"` |

On Kubernetes, use the Elastic Helm charts (or ECK) with the same `logstash.conf`;
pods are already annotated with `co.elastic.logs/enabled: "true"` by the Helm chart.
