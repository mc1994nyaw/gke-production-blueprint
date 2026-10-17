# Deploy the example

Complete [runbook.md](runbook.md) first. Run the commands below from a terminal where `gcloud auth login` and `gcloud auth application-default login` have already succeeded.

Set these once in that terminal. Use your real project id, the region you want, and a globally unique bucket name. `us-central1` is the placeholder region in `terraform.tfvars.example`, not a requirement.

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export STATE_BUCKET="your-unique-tfstate-bucket"
gcloud config set project "$PROJECT_ID"
```

`export` saves the values for later commands in this terminal. `gcloud config set project` makes `gcloud` use that project when a command does not pass `--project`.

`name_prefix` in the example tfvars is `gke-bp`. With that prefix, Terraform names resources like this:

| Resource | Name |
| --- | --- |
| VPC | `gke-bp-vpc` |
| Subnet | `gke-bp-nodes` |
| Cluster | `gke-bp-gke` |
| Node service account | `gke-bp-nodes@PROJECT_ID.iam.gserviceaccount.com` |
| Sample app service account | `gke-bp-sample@PROJECT_ID.iam.gserviceaccount.com` |

If you change `name_prefix`, those names change with it. The prefix must be 2 to 20 characters and match the rule in `terraform/variables.tf`.

## 1. Remote state bucket

**Costs money.** The bucket stores a small amount of object data, plus versions after the next command. It is not part of the Terraform module. The module cannot create the bucket it stores its own state in.

From any directory:

```bash
gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project "$PROJECT_ID" \
  --location "$REGION" \
  --uniform-bucket-level-access
```

This creates a Cloud Storage bucket in `$REGION` with uniform bucket-level access. Bucket names are global. If the name is taken, pick another and export `STATE_BUCKET` again.

```bash
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
```

Versioning keeps older copies of the state file. Do not commit the bucket name. `terraform.tfvars` is gitignored, and you will pass the bucket only to `terraform init`.

The state prefix inside the bucket is `gke-production-blueprint`, from `terraform/backend.tf` and the init command below.

## 2. Write terraform.tfvars

**Free.** This file is local. `.gitignore` ignores `*.tfvars` and keeps `*.tfvars.example`.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`cp` copies the example. Open `terraform.tfvars` and change at least the following.

`project_id` must be your project, in quotes:

```hcl
project_id = "your-project-id"
```

`region` must look like `us-central1` (letters, a hyphen, letters, one digit). The example value is `us-central1`.

### Control plane access

`enable_private_endpoint` defaults to `true`. Nodes are always private in this module (`enable_private_nodes` is hard-coded). The variable only controls whether the control plane has a public address.

`master_authorized_cidrs` in the example is `203.0.113.10/32`. That range is documentation space (RFC 5737). `kubectl` from your computer will not work until you replace it.

**Path A, recommended for a first run.** Keep private nodes, and allow your laptop to reach a public control plane endpoint. Set:

```hcl
enable_private_endpoint = false
```

Find your current public IPv4 address:

```bash
curl -4 ifconfig.me
echo
```

`curl` prints the address websites see. Replace the example block so `cidr_block` is that address plus `/32`:

```hcl
master_authorized_cidrs = [
  {
    cidr_block   = "YOUR_IP/32"
    display_name = "laptop"
  }
]
```

`YOUR_IP` is the address `curl` printed, with no spaces. Leave the `/32`.

**Path B, the example default.** Leave `enable_private_endpoint = true`. Your laptop cannot reach the control plane on the public internet. A VM in the subnet can, if that subnet is authorized. Add the subnet CIDR from the same file (`subnet_cidr`, example `10.10.0.0/20`):

```hcl
master_authorized_cidrs = [
  {
    cidr_block   = "10.10.0.0/20"
    display_name = "node-subnet"
  }
]
```

Use the `subnet_cidr` you actually set. Path B continues in [Reach a private endpoint](#5-reach-the-cluster) after apply. This repository does not contain a bastion. The VM in that section is created with `gcloud`, and it is not in the Terraform state.

`master_ipv4_cidr_block` must stay a `/28`. The example is `172.16.0.0/28`. `deletion_protection` should stay `true` until you are ready to destroy.

Leave the `node_pools` block as copied unless you already know you need different sizes. With the example:

- `system`: `e2-standard-2`, 50 GB `pd-balanced`, total min 1, max 3, no taint
- `application`: `e2-standard-2`, 50 GB, total min 1, max 5, taint `workload=app:NoSchedule`
- `logging`: `e2-standard-2`, 50 GB, total min 0, max 3, taint `workload=logging:NoSchedule`

`min_nodes` and `max_nodes` are totals for the whole region, not per zone. The logging pool stays at zero nodes because nothing in this repo tolerates that taint.

Confirm the tfvars file will not be committed:

```bash
git check-ignore -v terraform.tfvars
```

You should see `.gitignore` matching `*.tfvars`. `git status` should not list `terraform.tfvars`.

## 3. terraform init, plan, and apply

Stay in the `terraform/` directory.

```bash
terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=gke-production-blueprint"
```

`terraform init` downloads providers (already recorded in `.terraform.lock.hcl`) and connects the GCS backend. `-backend-config` supplies the bucket and prefix that `backend.tf` leaves empty. It does not create the cluster.

```bash
terraform plan
```

**Free** of cluster charges. `plan` asks Google Cloud what already exists, then prints what `apply` would create, change, or destroy. Read the plan. You want creates for the network, service accounts, cluster, and three node pools. You do not want destroys on a first run. `plan` writes nothing to the cloud except API reads.

```bash
terraform apply
```

**Costs money.** Type `yes` when prompted. `apply` creates:

- The VPC, subnet, Cloud Router, and Cloud NAT
- The node service account and the sample-app service account
- A regional private-node GKE cluster on the `REGULAR` release channel
- The three node pools

Google bills a regional cluster fee, the VMs and disks that stay up (`system` and `application` each keep at least one `e2-standard-2` and a 50 GB disk), Cloud NAT, VPC flow logs, and Cloud Logging for `SYSTEM_COMPONENTS` and `WORKLOADS`. The logging pool's minimum is 0, so it does not keep a VM.

`remove_default_node_pool` is true and `initial_node_count` is 1. That count is per zone. This configuration does not set node locations, and a regional GKE cluster uses three zones by default, so create briefly requests one node per zone in a pool Terraform then deletes. That short-lived pool is also billed for the time it exists.

Apply often takes 10 to 20 minutes. If it fails halfway, read the error, fix the cause, and run `terraform apply` again. Terraform will continue from the state in the bucket.

When it finishes, print the outputs:

```bash
terraform output
terraform output -raw get_credentials_command
terraform output -raw sample_app_gsa_email
```

`terraform output` prints names and emails. `get_credentials_command` is the exact `gcloud container clusters get-credentials` line for this cluster. `sample_app_gsa_email` is the Workload Identity email. You need it in the next section.

## 4. Point the sample app at that service account

**Free.** The committed manifest matches the placeholder project `example-project-id` and prefix `gke-bp`:

```text
gke-bp-sample@example-project-id.iam.gserviceaccount.com
```

That string is in `manifests/sample-app/serviceaccount.yaml` under `iam.gke.io/gcp-service-account`. Replace it with the email `terraform output -raw sample_app_gsa_email` just printed. If you kept `name_prefix = "gke-bp"`, the email is:

```text
gke-bp-sample@PROJECT_ID.iam.gserviceaccount.com
```

Save the file. podinfo does not call Google APIs, so the pods can still start with the wrong annotation. Workload Identity will not match your project until this line matches the output.

`manifests/sample-app/serviceaccount.yaml` is not gitignored. It will contain your project id after this edit. Leave it uncommitted if that id should stay private.

## 5. Reach the cluster

### Path A: public endpoint, private nodes

**Free** if the cluster already exists. From `terraform/`:

```bash
$(terraform output -raw get_credentials_command)
kubectl get nodes
```

The first line runs the output command. It writes a kubeconfig context for cluster `gke-bp-gke` (or your prefix) in `$REGION`. `kubectl get nodes` lists the nodes. You should see one `system` node and one `application` node, and no logging node while that pool's minimum is 0.

If this hangs or times out, the control plane is still private (`enable_private_endpoint = true`) or your current IP is not the `/32` in `master_authorized_cidrs`. Fix the tfvars and run `terraform apply` again, then retry.

### Path B: private endpoint

Use this only if you left `enable_private_endpoint = true` and added the subnet CIDR to `master_authorized_cidrs` before apply. **Costs money:** the bastion is an `e2-micro` with no public IP. Cloud NAT, already created by Terraform, carries its egress. Terraform will not delete this VM later. The teardown guide does.

From `terraform/`:

```bash
export PROJECT_ID="$(gcloud config get-value project)"
export REGION="$(terraform output -raw cluster_location)"
export NETWORK="$(terraform output -raw network_name)"
export SUBNET="$(terraform output -raw subnet_name)"
export CLUSTER="$(terraform output -raw cluster_name)"
gcloud compute zones list --filter="region:${REGION}" --format="value(name)"
```

`terraform output -raw` prints a single value with no quotes. The zones command lists zones in the cluster's region, one per line. Pick one that exists. This configuration does not choose a zone for you. Example: if the list includes `us-central1-b`, you can use that.

```bash
export ZONE="us-central1-b"
```

Replace that with a zone from the list you just printed.

```bash
gcloud compute instances create gke-bp-bastion \
  --project="${PROJECT_ID}" \
  --zone="${ZONE}" \
  --machine-type=e2-micro \
  --network="${NETWORK}" \
  --subnet="${SUBNET}" \
  --no-address \
  --tags=gke-bp-bastion \
  --scopes=https://www.googleapis.com/auth/cloud-platform
```

This creates a Debian VM on the node subnet, with no external IP, tagged `gke-bp-bastion`.

```bash
gcloud compute firewall-rules create gke-bp-allow-iap-ssh \
  --project="${PROJECT_ID}" \
  --network="${NETWORK}" \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=gke-bp-bastion
```

**Free.** `35.235.240.0/20` is Google's published range for IAP TCP forwarding. The rule allows SSH from IAP to VMs with the bastion tag. It does not open SSH to the internet.

```bash
gcloud compute ssh gke-bp-bastion \
  --project="${PROJECT_ID}" \
  --zone="${ZONE}" \
  --tunnel-through-iap
```

This opens a shell on the VM through IAP. The commands from here until `exit` run on the bastion.

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin kubectl
gcloud auth login --no-launch-browser
gcloud config set project PROJECT_ID
gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT_ID
kubectl get nodes
```

Replace `PROJECT_ID`, `CLUSTER`, and `REGION` with the values from your laptop. `gcloud auth login --no-launch-browser` prints a URL. Open it on your laptop, then paste the code back into the bastion. `get-credentials` writes kubeconfig on the bastion. `kubectl get nodes` should list the nodes.

Stay on the bastion for the Helm and `kubectl apply` steps, or install Helm there too (`curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`). The manifest files are on your laptop. Copy the repo onto the bastion, or use Path A. Type `exit` when you are done with the SSH session.

If `kubectl get nodes` on the bastion times out, the subnet CIDR is not what GKE is allowing. On your laptop, print the VM's internal address and add it to `master_authorized_cidrs` as a `/32`, then `terraform apply` and try again:

```bash
gcloud compute instances describe gke-bp-bastion \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}" \
  --format='value(networkInterfaces[0].networkIP)'
```

## 6. Install kube-prometheus-stack

**Costs money.** The values file requests a 50 GB persistent disk for Prometheus (`monitoring/kube-prometheus-stack-values.yaml`, `storage: 50Gi`). Prometheus and Grafana schedule onto the untainted system pool. The example system pool is one `e2-standard-2`. If the pods stay `Pending`, the operations guide explains how to see why.

Run this from the **repository root** on a machine whose `kubectl` already works (your laptop on Path A, or the bastion after you clone the repo there).

```bash
cd /path/to/gke-production-blueprint
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

`helm repo add` records the chart repository. `helm repo update` downloads its index. Chart `92.10.1` is the version the values file was written for.

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 92.10.1 \
  --values monitoring/kube-prometheus-stack-values.yaml
```

`upgrade --install` installs the release named `kube-prometheus-stack` if it is missing, or upgrades it if it is already there. `--namespace monitoring` puts it in the `monitoring` namespace. `--create-namespace` creates that namespace. `--version 92.10.1` pins the chart. `--values` applies the file in this repo, including `fullnameOverride: kube-prometheus-stack`.

The chart creates the Prometheus Operator CRDs. The next `kubectl apply` needs those CRDs. Wait until the pods are up:

```bash
kubectl get pods -n monitoring
```

Repeat until `prometheus`, `grafana`, and `alertmanager` pods are `Running`. A few jobs may complete and disappear. That is normal.

The Grafana admin password is not in git. The chart generates it. List secrets, then read the password. The secret name for this release and `fullnameOverride` is `kube-prometheus-stack-grafana`. If `kubectl get secret` shows a different grafana secret, use that name.

```bash
kubectl get secret -n monitoring
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-user}' | base64 -d
echo
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
echo
```

`jsonpath` selects one field. `base64 -d` decodes it. On macOS, if `-d` is rejected, use `base64 -D` instead. The user is usually `admin`. Keep the password for the next section. Do not commit it.

## 7. Apply the monitoring manifests and the sample app

**Free** of new Google VMs. The sample app runs on the application pool you are already paying for.

Still at the repository root, and only after the Helm release above has installed CRDs:

```bash
kubectl apply -k monitoring
kubectl apply -k manifests/sample-app
```

`kubectl apply -k monitoring` builds `monitoring/kustomization.yaml`. That creates the `monitoring` namespace if needed, the `PrometheusRule` `sample-app-slo`, and a ConfigMap `sample-app-dashboard` labeled `grafana_dashboard=1`.

`kubectl apply -k manifests/sample-app` builds `manifests/sample-app/kustomization.yaml`. That creates the namespace, ServiceAccount, Deployment, Service, HPA, PodDisruptionBudget, NetworkPolicies, and ServiceMonitor.

If `kubectl apply -k monitoring` says the `PrometheusRule` CRD is missing, the Helm install has not finished. Wait, then run the same command again.

Watch the sample pods:

```bash
kubectl get pods -n sample-app -o wide
kubectl get pods -n monitoring
```

`sample-app` pods should become `Running`. They require a node labeled `node-pool=application` and they tolerate `workload=app:NoSchedule`. That matches `terraform/modules/gke` and `manifests/sample-app/deployment.yaml`.

## 8. Open Grafana and the dashboard

The chart sidecar loads every ConfigMap with label `grafana_dashboard=1` in any namespace (`searchNamespace: ALL` in the values file). Applying `monitoring/` is the import. You can also upload the JSON by hand.

Port-forward Grafana. The service port in the chart is 80. Confirm with `kubectl get svc -n monitoring` if the port column is not `80`.

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

This stays running. Leave the terminal open. On your computer, open `http://127.0.0.1:3000`. Log in with the user and password from the secret.

In Grafana: Dashboards, then search for **Sample app (example)**. The dashboard uid in `monitoring/dashboards/sample-app.json` is `gke-bp-sample-app`. The panels are request rate, error ratio, latency p99, and pod restarts. They are labeled example. With no traffic yet, the request panels are empty. That is expected. The next section generates a few requests.

If the dashboard is missing, in another terminal:

```bash
kubectl get configmap -n monitoring sample-app-dashboard --show-labels
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].spec.containers[*].name}'
echo
```

The labels must include `grafana_dashboard=1`. Then read the sidecar container log. The Grafana chart names that container `grafana-sc-dashboard`:

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=50
```

To import by hand instead: in Grafana choose Dashboards, New, Import, and upload `monitoring/dashboards/sample-app.json`. When asked for a data source, pick Prometheus. The JSON uses datasource uid `prometheus`, which is the uid the chart creates.

Stop the port-forward with Ctrl-C when you are finished with the UI.

## 9. Verify

**Free** apart from the cluster you are already running. Use a new terminal at the repository root, with the same kubeconfig.

Nodes and labels:

```bash
kubectl get nodes -L node-pool,role
```

`-L` adds the labels Terraform sets: `node-pool` is `system` or `application`, and `role` comes from `terraform.tfvars`.

Sample app objects:

```bash
kubectl get deploy,svc,hpa,pdb,networkpolicy,servicemonitor -n sample-app
```

You want Deployment `sample-app` ready, Service `sample-app` with ports `9898` and `9797`, HPA min 2 max 6, PodDisruptionBudget `maxUnavailable` 1, three NetworkPolicies (`default-deny`, `allow-dns-and-metadata`, `allow-http-and-metrics`), and ServiceMonitor `sample-app`.

Call the app through the Service:

```bash
kubectl port-forward -n sample-app svc/sample-app 9898:9898
```

Leave that running. In a second terminal:

```bash
curl -fsS http://127.0.0.1:9898/healthz
echo
curl -fsS http://127.0.0.1:9898/readyz
echo
curl -fsS http://127.0.0.1:9898/ | head
```

`/healthz` and `/readyz` are the probe paths in the Deployment. `/` returns podinfo's runtime page. `curl -f` fails on HTTP errors. Repeat the `/` curl a few times so Prometheus has samples.

Metrics from the same Service, port `9797`, path `/metrics`. Stop the previous port-forward or use another local port. This one uses 9797:

```bash
kubectl port-forward -n sample-app svc/sample-app 9797:9797
```

Second terminal:

```bash
curl -fsS http://127.0.0.1:9797/metrics | head
```

You should see Prometheus text, including `http_request_duration_seconds`.

Prometheus itself:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Open `http://127.0.0.1:9090/targets` and find a target for `sample-app` in namespace `sample-app` that is `UP`. In the query box, run the same expression the recording rule uses:

```text
sum(rate(http_request_duration_seconds_count{namespace="sample-app"}[5m]))
```

After the curls, this should be a number greater than zero within a few minutes. The recording rules and alerts are in `monitoring/prometheusrule.yaml`. They do not fire just because the app is healthy. `SampleAppErrorBudgetBurn` waits one hour, and `SampleAppLatencyHigh` waits ten minutes, and both require traffic. Empty graphs before any curls are normal.

Alertmanager:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Open `http://127.0.0.1:9093`. A quiet Alertmanager after a fresh install is a successful check.

HPA can read CPU because the cluster enables the Horizontal Pod Autoscaler addon and GKE provides metrics-server:

```bash
kubectl top pods -n sample-app
kubectl get hpa -n sample-app
```

`kubectl top` fails until metrics-server has been up for a minute. Run it again. The HPA target is 70% CPU. The Deployment requests `50m` CPU, so the percentage is based on that request.

When these checks pass, the example is up. Continue with [day-2 operations and teardown](runbook-operations.md) before you leave the cluster running.
