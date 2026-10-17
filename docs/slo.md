# Sample app SLO (example)

These targets are **examples**. Nothing in this repository has been deployed, and no traffic has been measured. Do not quote them as the reliability of a running system.

The workload is [podinfo](https://github.com/stefanprodan/podinfo) `6.15.0` in the `sample-app` namespace. Prometheus rules that implement the queries live in `monitoring/prometheusrule.yaml`.

## User journey

An in-cluster client calls the sample app over HTTP on port 9898 and gets a non-5xx response.

## Availability

| Item | Example value |
| --- | --- |
| SLI | Share of requests whose `status` label is not 5xx |
| Query | `sample_app:http_request_success_ratio:rate5m` |
| Target | 99.9% of requests over a rolling 30 days |
| Error budget | 0.1% of requests, which is 43.2 minutes of full outage in 30 days (`30 * 24 * 60 * 0.001`) |

The recording rule uses podinfo's `http_request_duration_seconds_count` histogram and its `status` label. With no traffic the ratio is empty, and the example burn alert stays quiet because it also requires a non-zero request rate.

The example alert `SampleAppErrorBudgetBurn` pages when the 5 minute error rate stays above `14.4 * 0.001` (1.44%) for 1 hour. That is the SRE workbook fast-burn hint for consuming about 2% of a 30 day 0.1% budget in one hour. It is one example rule, not a multi-window paging policy.

## Latency

| Item | Example value |
| --- | --- |
| SLI | 99th percentile of `http_request_duration_seconds` |
| Query | `sample_app:http_request_duration_seconds:p99` |
| Target | 300ms |
| Alert | `SampleAppLatencyHigh` after 10 minutes above 300ms, and only when requests are flowing |

## What would make this real

Pick the target with the people who use the service, after the app is installed and the histogram has data. Replace the numbers in this file and in `monitoring/prometheusrule.yaml` together. Until then, treat every figure on this page as an illustration of the SLO shape.
