# Day-2 operations, incidents, and teardown

The cluster from [runbook-deploy.md](runbook-deploy.md) is assumed to be up, and `kubectl` works. Commands that change Terraform run from the `terraform/` directory. Commands that apply manifests run from the repository root.

Anything that raises `min_nodes`, enlarges disks, or adds a VM is marked **Costs money**. Reading status is **Free**.

## Scaling

### Sample app (HPA)

The Horizontal Pod Autoscaler is `manifests/sample-app/hpa.yaml`. It keeps between 2 and 6 pods and targets 70% of the CPU request (`50m` in the Deployment). Scale-down waits 300 seconds. The Deployment's `replicas: 2` matches the HPA minimum.

See the live object:

```bash
kubectl get hpa -n sample-app
kubectl describe hpa -n sample-app
```

`get` prints current and desired replicas. `describe` prints the CPU signal and the last scale event.

To change the maximum, edit `maxReplicas` in `manifests/sample-app/hpa.yaml`, then:

```bash
kubectl apply -k manifests/sample-app
```

`kubectl apply -k` updates the HPA and the rest of the sample app from the files in the repo. More replicas fit on the application pool only while that pool has CPU. The example pool maximum is 5 nodes (`max_nodes` in `terraform.tfvars`). If pods stay `Pending`, raise that maximum with the Terraform steps below. **Costs money** once new nodes exist. The HPA object itself does not.

Do not `kubectl scale deployment sample-app` to hold a fixed replica count. The HPA will change it again.

### Node pools (Cluster Autoscaler)

Autoscaling bounds are `min_nodes` and `max_nodes` inside `node_pools` in `terraform/terraform.tfvars`. Terraform maps them to `total_min_node_count` and `total_max_node_count` on each `google_container_node_pool`. Those totals are for the whole region.

The logging pool's example minimum is 0. No manifest in this repo tolerates `workload=logging:NoSchedule`, so that pool stays empty. Raising `logging.min_nodes` above 0 **costs money** for VMs that no pod in this repo uses.

From `terraform/`:

```bash
terraform plan
terraform apply
```

`plan` shows whether a node pool's autoscaling block will change. `apply` updates the cluster. **Costs money** if the new minimum is higher than the number of nodes already running.

Watch nodes:

```bash
kubectl get nodes -L node-pool,role
```

## Upgrades

Node pools set `auto_repair` and `auto_upgrade` to true. The cluster `release_channel` in the example tfvars is `REGULAR`. Allowed values in `terraform/variables.tf` are `RAPID`, `REGULAR`, `STABLE`, and `EXTENDED`.

The maintenance window is not in `terraform.tfvars.example`. The defaults in `terraform/variables.tf` are:

- `maintenance_start` = `2026-01-04T09:00:00Z`
- `maintenance_end` = `2026-01-04T13:00:00Z`
- `maintenance_recurrence` = `FREQ=WEEKLY;BYDAY=SU`

The date is only an anchor. The recurrence is Sunday, 09:00 to 13:00 UTC.

**Free** to inspect:

```bash
cd terraform
gcloud container clusters describe "$(terraform output -raw cluster_name)" \
  --region "$(terraform output -raw cluster_location)" \
  --project "$(gcloud config get-value project)" \
  --format='yaml(currentMasterVersion,releaseChannel,maintenancePolicy)'
gcloud container operations list \
  --region "$(terraform output -raw cluster_location)"
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,POOL:.metadata.labels.node-pool
```

`clusters describe` prints the master version, channel, and window. `operations list` shows upgrades GKE is running. The `kubectl` line prints each node's kubelet version and pool label.

To change the channel or the window, set the variables in `terraform.tfvars` and run `terraform apply`. GKE can reject a channel change that skips versions. If apply prints that error, leave the channel as it is and let the current channel finish its upgrades. Do not delete the cluster to force a version.

## Rotating credentials

This Terraform creates no JSON keys and no Grafana password in git.

### Your user login

**Free.**

```bash
gcloud auth revoke
gcloud auth login
gcloud auth application-default login
```

`revoke` drops the stored user credential. The two `login` commands issue a new one. Terraform uses application-default credentials. This does not rotate the node service account. The cluster keeps running.

### Service account keys

Confirm Terraform did not leave a user-managed key. From `terraform/`:

```bash
gcloud iam service-accounts keys list \
  --iam-account="$(terraform output -raw node_service_account_email)" \
  --filter="keyType=USER_MANAGED"
gcloud iam service-accounts keys list \
  --iam-account="$(terraform output -raw sample_app_gsa_email)" \
  --filter="keyType=USER_MANAGED"
```

An empty list is what this module produces. Nodes use the attached service account, and the sample app uses Workload Identity. If a `USER_MANAGED` key is listed because someone created one later, delete that key id:

```bash
gcloud iam service-accounts keys delete KEY_ID \
  --iam-account="EMAIL"
```

`keys delete` removes that key. Anything still using the downloaded file stops working. Google-managed keys are not in this filtered list. Leave those alone.

### Grafana admin password

The chart stores the generated password in the Grafana secret and injects it when the pod starts. Rotate it without editing the values file.

Confirm the secret and deployment names:

```bash
kubectl get secret -n monitoring
kubectl get deploy -n monitoring
```

For release name `kube-prometheus-stack` and `fullnameOverride: kube-prometheus-stack`, they are `kube-prometheus-stack-grafana`.

```bash
NEW="$(openssl rand -base64 18)"
ENC="$(printf '%s' "$NEW" | base64 | tr -d '\n')"
kubectl patch secret -n monitoring kube-prometheus-stack-grafana --type=json \
  -p="[{\"op\":\"replace\",\"path\":\"/data/admin-password\",\"value\":\"${ENC}\"}]"
kubectl rollout restart deployment -n monitoring kube-prometheus-stack-grafana
printf '%s\n' "$NEW"
```

`openssl` makes a new password. `base64` encodes it the way a Secret expects. `kubectl patch` replaces `admin-password`. `rollout restart` restarts Grafana so it reads the new value. The last line prints the password once. Store it somewhere private. Do not commit it.

## Incident response

Two alerts are defined in this repo, in `monitoring/prometheusrule.yaml`. Both have label `example: "true"`. The thresholds match [docs/slo.md](slo.md) and were not measured from a running service. Treat them as practice for the shape of a response, not as an agreed page.

kube-prometheus-stack also installs its own rules because `defaultRules.create` is true. The values file turns off etcd, kube-controller-manager, kube-scheduler, kube-proxy, and Windows rules. List every alert name actually installed:

```bash
kubectl get prometheusrule -n monitoring -o yaml | grep 'alert:'
```

**Free.** If a name below is not in that list, that rule is not loaded. Skip that playbook.

Open Alertmanager while you work:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Browse `http://127.0.0.1:9093`. Prometheus alerts are at `http://127.0.0.1:9090/alerts` after:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

### SampleAppErrorBudgetBurn

**What it means.** For one hour, the 5-minute error ratio is above `14.4 * 0.001` (1.44%) and the sample app is receiving requests. The recording rule is `sample_app:http_request_success_ratio:rate5m`. It treats any `status` label matching `5..` as an error. The app is podinfo with `--random-error=false`, so a quiet install should not fire this.

**Symptoms.** Alertmanager shows `SampleAppErrorBudgetBurn` in namespace `monitoring`, severity `warning`. The Grafana "Error ratio (example)" panel is above zero.

**Diagnosis.**

```bash
kubectl get pods -n sample-app -o wide
kubectl describe pods -n sample-app
kubectl logs -n sample-app -l app.kubernetes.io/name=sample-app --tail=100
kubectl get events -n sample-app --sort-by='.lastTimestamp'
```

`describe` shows restarts and probe failures. `logs` shows what podinfo printed. In Prometheus, run:

```text
sum(rate(http_request_duration_seconds_count{namespace="sample-app",status=~"5.."}[5m]))
sum(rate(http_request_duration_seconds_count{namespace="sample-app"}[5m]))
sample_app:http_request_success_ratio:rate5m
```

podinfo answers `GET /status/500` with HTTP 500. A client calling that path will trip the example alert. The probes use `/healthz` and `/readyz`, which are not 5xx when the process is healthy.

**Mitigation.**

1. Find who is calling `/status/5xx` and stop that client.
2. If one pod is crash-looping, delete that pod and let the Deployment replace it:

```bash
kubectl delete pod -n sample-app POD_NAME
```

3. If the process is up and the ratio is only slightly above the example line, this alert is doing what the example rule says. Change the threshold in `monitoring/prometheusrule.yaml` and the same number in `docs/slo.md` together, then `kubectl apply -k monitoring`. Do not treat 99.9% as a commitment this repo measured.

The alert stays quiet when there is no traffic, because the expression requires the request rate to be greater than zero.

### SampleAppLatencyHigh

**What it means.** For 10 minutes, `sample_app:http_request_duration_seconds:p99` is above 0.3 seconds while requests are arriving. The Deployment sets `--random-delay=false`. The CPU limit on the container is `250m`.

**Symptoms.** The alert is firing and the Grafana "Latency p99 (example)" panel is above 300ms.

**Diagnosis.**

```bash
kubectl top pods -n sample-app
kubectl describe pods -n sample-app
kubectl logs -n sample-app -l app.kubernetes.io/name=sample-app --tail=100
```

`kubectl top` shows CPU against the `50m` request. In Prometheus:

```text
sample_app:http_request_duration_seconds:p99
```

podinfo's `GET /delay/1` waits one second and will push this example alert over 300ms.

**Mitigation.**

1. Stop clients that call `/delay/...`.
2. If CPU is near the limit, either raise `maxReplicas` in the HPA (see [Scaling](#scaling)) or raise the application pool `max_nodes` and apply Terraform. A larger pool **costs money**.
3. If the example 300ms line is tighter than you want for a demo, edit the `> 0.3` comparison in `monitoring/prometheusrule.yaml` and the latency target in `docs/slo.md`, then `kubectl apply -k monitoring`.

### Chart alerts you are likely to see

These names come from kube-prometheus-stack's default rules, not from a file of thresholds in this repo. Confirm each one with the `grep 'alert:'` command above before you follow it.

#### KubePodNotReady or KubePodCrashLooping

**Symptoms.** A pod in `sample-app` or `monitoring` is `Pending`, `CrashLoopBackOff`, or not Ready. Alertmanager names the pod.

**Diagnosis.**

```bash
kubectl get pods -A
kubectl describe pod -n NAMESPACE POD_NAME
kubectl logs -n NAMESPACE POD_NAME --tail=100
kubectl get events -n NAMESPACE --sort-by='.lastTimestamp'
```

Read the `Events` at the bottom of `describe`. `FailedScheduling` means the pod cannot find a node. Sample-app pods need label `node-pool=application` and tolerate `workload=app:NoSchedule`. Monitoring pods do not tolerate that taint, so they belong on the system pool.

**Mitigation.** If the application pool has no Ready node, `terraform apply` is how you change `node_pools.application`. If a monitoring pod says `Insufficient cpu` or `Insufficient memory`, the example `e2-standard-2` system pool is too small for the requests in the values file (Prometheus asks for `512Mi` memory and `200m` CPU). Set `node_pools.system.machine_type` to a larger type in `terraform.tfvars` and apply. **Costs money.**

#### KubeNodeNotReady

**Symptoms.** `kubectl get nodes` shows `NotReady`. The cluster has `auto_repair` enabled.

**Diagnosis.**

```bash
kubectl get nodes -o wide
kubectl describe node NODE_NAME
gcloud container operations list --region REGION
```

**Mitigation.** Wait for the repair operation if one is listed. If the node stays `NotReady`, `kubectl describe node` events are the next clue (disk pressure, network). Do not delete the node object by hand. GKE owns the nodes. Changing the pool is a Terraform apply.

#### TargetDown

**Symptoms.** Prometheus reports a target as down. For this repo the one you added is ServiceMonitor `sample-app`, port `metrics` (9797), path `/metrics`.

**Diagnosis.**

```bash
kubectl get pods -n sample-app
kubectl get servicemonitor -n sample-app -o yaml
kubectl get networkpolicy -n sample-app
```

`manifests/sample-app/networkpolicy.yaml` denies all traffic, then allows namespace `monitoring` to reach ports 9797 and 9898. Prometheus must run in namespace `monitoring`. The namespace label `kubernetes.io/metadata.name=monitoring` is set in `monitoring/namespace.yaml` and by Kubernetes itself.

**Mitigation.** If the sample pods are not Running, fix that first. If Prometheus is in a different namespace than `monitoring`, the NetworkPolicy will drop the scrape. Reinstall with the Helm command in the deploy guide so the release stays in `monitoring`.

#### NodeFilesystemSpaceFillingUp or similar node disk alerts

**Symptoms.** A node disk alert from the chart's node rules. Example node disks are 50 GB `pd-balanced`.

**Diagnosis.**

```bash
kubectl describe node NODE_NAME
```

Look for `DiskPressure`.

**Mitigation.** The logging and monitoring data on the node can fill a 50 GB disk. Raising `disk_size_gb` for that pool in `terraform.tfvars` and applying **costs money** and may recreate nodes. Deleting the sample namespace does not shrink the disk. Emptying the cluster with the teardown steps removes the disks with the nodes.

## Troubleshooting

| What you see | What it means here | What to run |
| --- | --- | --- |
| `terraform init` asks for a bucket or backend config | `backend.tf` is an empty `backend "gcs" {}` | Re-run init with `-backend-config="bucket=..."` and `-backend-config="prefix=gke-production-blueprint"` |
| `Error: Invalid value for variable` on `project_id` | The id fails the regex in `terraform/variables.tf` | Use 6–30 lowercase characters, starting with a letter |
| `master_ipv4_cidr_block must be a /28` | The control plane range is not a /28 | Keep `172.16.0.0/28` or another `/28` |
| `name_prefix` validation error | Prefix length or characters | 2–20 chars, lowercase, must not end with a hyphen. Example `gke-bp` |
| `kubectl` times out after `get-credentials` | Private endpoint, or your IP is not authorized | Path A or Path B in the deploy guide. The example CIDR `203.0.113.10/32` is not your IP |
| `terraform destroy` refuses, deletion protection | `deletion_protection` defaults to true | Set it to `false`, `terraform apply`, then `terraform destroy`. See [Teardown](#teardown) |
| `no matches for kind "PrometheusRule"` or `ServiceMonitor` | CRDs are not installed yet | Run the Helm install, wait for pods, then `kubectl apply -k` again |
| Sample pods `Pending`, taint `workload=app` | They are waiting for the application pool | `kubectl describe pod -n sample-app` and `kubectl get nodes -L node-pool` |
| Monitoring pods `Pending` on CPU or memory | Example system pool is one `e2-standard-2` | Raise `node_pools.system.machine_type` or `max_nodes` and apply. **Costs money** |
| Grafana has no "Sample app (example)" dashboard | ConfigMap label or sidecar | `kubectl get configmap -n monitoring sample-app-dashboard --show-labels` must show `grafana_dashboard=1`. Then import `monitoring/dashboards/sample-app.json` by hand |
| Prometheus target for sample-app is `DOWN` | NetworkPolicy or pods down | Pods must be Running in `sample-app`. Prometheus must be in `monitoring` |
| `kubectl top` says metrics not available | metrics-server is still starting | Wait a minute and run it again. The addon is enabled in `terraform/modules/gke` |
| `Error 403` or `API not enabled` on apply | The first apply enables APIs; a second apply usually clears this | Run `terraform apply` again after the enable finishes. The API list is in `terraform/main.tf` |
| `terraform.tfvars` showed up in `git status` | The ignore rule did not match the path | The file must be named `terraform.tfvars` under `terraform/`. `git check-ignore -v terraform/terraform.tfvars` |

CI does not run `plan` or `apply`. A green GitHub Actions check does not mean a cluster exists.

## Teardown

**Costs money until this finishes.** Nodes, Cloud NAT, the regional cluster fee, and the 50 GB Prometheus disk keep billing while they exist. `terraform destroy` often takes as long as apply. Check Billing the next day for leftovers. A budget alert does not delete anything.

Do this from the repository root first, while `kubectl` still works, so the 50 GB disk is deleted with its PersistentVolumeClaim. The default StorageClass reclaim policy is Delete.

```bash
helm uninstall kube-prometheus-stack --namespace monitoring
kubectl delete pvc --all --namespace monitoring
kubectl delete -k manifests/sample-app
kubectl delete -k monitoring
```

`helm uninstall` removes the monitoring release. `kubectl delete pvc` removes the Prometheus volume. The two `kubectl delete -k` commands remove the sample app and the PrometheusRule and dashboard ConfigMap. The namespaces may remain empty. That is fine.

If you created the manual bastion, delete it before Terraform. It is not in state, and a VM still attached to the subnet can make `terraform destroy` fail. **This stops the e2-micro charge.**

```bash
gcloud compute instances delete gke-bp-bastion --zone=ZONE --project=PROJECT_ID
gcloud compute firewall-rules delete gke-bp-allow-iap-ssh --project=PROJECT_ID
```

Use the same `ZONE` and `PROJECT_ID` as in the deploy guide. Confirm the names if you changed them:

```bash
gcloud compute instances list --project=PROJECT_ID
gcloud compute firewall-rules list --project=PROJECT_ID
```

Turn deletion protection off. In `terraform/terraform.tfvars` set:

```hcl
deletion_protection = false
```

From `terraform/`:

```bash
terraform apply
terraform destroy
```

`apply` writes `deletion_protection = false` into state. Destroy is blocked until that apply succeeds. `terraform destroy` then deletes the cluster, node pools, Cloud NAT, subnet, VPC, and the two service accounts. Type `yes`. **This is the step that stops the cluster bill.** It does not delete the state bucket.

Confirm the big resources are gone:

```bash
gcloud container clusters list --project=PROJECT_ID
gcloud compute networks list --project=PROJECT_ID
gcloud compute disks list --project=PROJECT_ID
gcloud compute addresses list --project=PROJECT_ID
```

`clusters list` should be empty. `disks list` should not still show the 50 GB Prometheus disk. If a disk remains, delete it by the name printed there:

```bash
gcloud compute disks delete DISK_NAME --zone=ZONE --project=PROJECT_ID
```

**Costs money** until that disk is gone.

The state bucket is still there and still has a small storage charge. After `terraform destroy` has succeeded and you do not need the state, set `STATE_BUCKET` to the same name you passed to `terraform init`, then:

```bash
gcloud storage rm --recursive "gs://${STATE_BUCKET}"
gcloud storage buckets delete "gs://${STATE_BUCKET}"
```

`rm` deletes objects. `buckets delete` deletes the bucket. This removes Terraform state. Do it only after destroy.

The budget from the first guide does not cost money. You can leave it. To see it:

```bash
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID
```

Deleting the whole project also stops billing on anything still inside it:

```bash
gcloud projects delete PROJECT_ID
```

That is optional, and it is not reversible for a while. You do not need it if `clusters list`, `disks list`, and the state bucket are already clean.
