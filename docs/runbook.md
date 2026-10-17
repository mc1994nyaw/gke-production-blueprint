# Runbook

Start here if you have never used this repository. The steps use the files that are already in the tree. They do not invent a second cluster layout.

Follow the guides in order:

1. This page: tools, a Google Cloud project, billing, and a budget.
2. [Deploy](runbook-deploy.md): remote state, `terraform.tfvars`, apply, reach the cluster, install the sample app and kube-prometheus-stack, import the dashboard, and check that it works.
3. [Day-2, incidents, and teardown](runbook-operations.md): scaling, upgrades, credentials, the alerts in this repo, common errors, and `terraform destroy`.

[docs/slo.md](slo.md) explains the example 99.9% and 300ms numbers. Those numbers are illustrations. They are not measurements from a live cluster.

## What "costs money" means

A step marked **Costs money** creates or keeps Google Cloud resources that appear on a bill. A step marked **Free** does not create those resources. Budgets send email. They do not stop the bill. Prices change, and this runbook does not quote a price for the cluster. Set a budget you are willing to notice, then destroy the stack when you are done. The [teardown](runbook-operations.md#teardown) section is the way to stop the charges this repo creates.

Leaving the cluster up overnight still costs money. `terraform apply` is the step that starts that spend.

## 1. Get the code

**Free.**

```bash
git clone <repository-url>
cd gke-production-blueprint
```

`git clone` downloads the repository. `cd` moves into it. Later commands assume this directory is the repository root unless they say `cd terraform`.

Replace `<repository-url>` with the URL of your clone. The rest of the commands are the same either way.

## 2. Install the tools

You need four tools on the machine where you will run Terraform and `kubectl`.

| Tool | Version this repo expects | What it does |
| --- | --- | --- |
| Google Cloud CLI (`gcloud`) | Current stable | Logs you in and talks to Google Cloud |
| Terraform | 1.10.0 or newer. CI uses 1.16.6 | Creates the VPC and cluster from `terraform/` |
| kubectl | A current release | Talks to the cluster after it exists |
| Helm | 3 | Installs kube-prometheus-stack chart `92.10.1` |

`kubectl apply -k` is built into kubectl. You do not need a separate `kustomize` binary to deploy. CI uses kustomize 5.8.3, kubeconform 0.8.0, tflint 0.64.0, and yamllint 1.35.1 only to check pull requests. Those four are optional on your laptop.

Check what you already have:

```bash
gcloud version
terraform version
kubectl version --client
helm version
```

Each command prints a version, or the shell says the program is missing.

### Google Cloud CLI and kubectl

**Free.**

Debian or Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update
sudo apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin kubectl
```

`apt-get update` refreshes package lists. The `curl` and `echo` lines add Google's package repository. `google-cloud-cli` is the `gcloud` program. `google-cloud-cli-gke-gcloud-auth-plugin` is required for `kubectl` to authenticate to GKE. `kubectl` is the Kubernetes CLI from the same repository.

macOS with Homebrew:

```bash
brew install --cask gcloud-cli
brew install kubernetes-cli
gcloud components install gke-gcloud-auth-plugin
```

`gcloud-cli` is the current Homebrew cask. `kubernetes-cli` installs `kubectl`. The last command installs the GKE auth plugin into the Cloud SDK.

If the apt package names fail on your distribution, use the installer on [the Cloud SDK install page](https://cloud.google.com/sdk/docs/install) and then run `gcloud components install kubectl gke-gcloud-auth-plugin`.

### Terraform 1.16.6

**Free.**

`terraform/versions.tf` requires Terraform 1.10.0 or newer. 1.16.6 is the version CI installs. This zip is the Linux amd64 build:

```bash
curl -fsSL -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.16.6/terraform_1.16.6_linux_amd64.zip
sudo unzip -o /tmp/terraform.zip -d /usr/local/bin terraform
terraform version
```

`curl` downloads the archive. `unzip` copies only the `terraform` binary into `/usr/local/bin`. `terraform version` should print `Terraform v1.16.6`.

On Apple silicon, use `terraform_1.16.6_darwin_arm64.zip`. On Intel Macs, use `terraform_1.16.6_darwin_amd64.zip`. On Linux arm64, use `terraform_1.16.6_linux_arm64.zip`.

### Helm 3

**Free.**

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

The script installs Helm 3. `helm version` should show `v3`.

### Log in to Google Cloud

**Free.** This does not create resources. It stores credentials on your computer.

```bash
gcloud auth login
gcloud auth application-default login
```

`gcloud auth login` is the identity used by `gcloud` commands. `gcloud auth application-default login` is the identity Terraform uses. Complete both browser prompts. Do not download a service-account JSON key for this. The Terraform in this repo does not read a key file.

## 3. Check the checkout before you spend anything

**Free.** These are the same Terraform checks CI runs. They do not create a cluster and do not need a state bucket.

From the repository root:

```bash
terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
```

`terraform fmt -check` fails if a `.tf` file is not formatted. `-recursive` includes the modules. `terraform -chdir=terraform` runs Terraform inside `terraform/` without you having to `cd` there. `init -backend=false` downloads the Google provider and skips the remote state bucket. `validate` checks that the configuration is internally consistent.

A successful validate ends with `Success! The configuration is valid.`

## 4. Choose or create a project

You need a project id that matches the rule in `terraform/variables.tf`: 6 to 30 characters, lowercase letters, digits, and hyphens, starting with a letter and ending with a letter or digit. `example-project-id` in `terraform.tfvars.example` is a placeholder. It is not a project you can apply.

List projects you can already use:

```bash
gcloud projects list
```

**Free.** This prints project ids. If you will use one of them:

```bash
gcloud config set project PROJECT_ID
```

That sets the default project for later `gcloud` commands in this terminal.

To create a new project instead:

```bash
gcloud projects create PROJECT_ID --name="GKE blueprint example"
gcloud config set project PROJECT_ID
```

`gcloud projects create` reserves the id. Creating an empty project does not start GKE charges. The id must be unique across Google Cloud. If your account has no permission to create projects, use one from `gcloud projects list`.

For the rest of the runbook, `PROJECT_ID` means the id you just selected.

## 5. Billing and a budget alert

GKE, Cloud NAT, disks, and the monitoring volume will not create until a billing account is linked. Linking billing does not by itself start those resources. The charges start at `terraform apply` in the [deploy guide](runbook-deploy.md).

List billing accounts your user can use:

```bash
gcloud billing accounts list
```

**Free.** Copy the `ACCOUNT_ID` value. Link it:

```bash
gcloud billing projects link PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
```

This attaches the project to that billing account. Confirm:

```bash
gcloud billing projects describe PROJECT_ID
```

The output should show `billingEnabled: true`.

Create a budget so you get email before the month's spend gets away from you. **Free** (the budget does not cap spend). `25USD` below is an example alarm, not a price for this stack. Change it to whatever amount you want to hear about. Thresholds are fractions: `0.5` means 50 percent.

```bash
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="gke-blueprint example" \
  --budget-amount=25USD \
  --filter-projects=projects/PROJECT_ID \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0
```

`--filter-projects` limits the budget to this project. The default emails go to billing account administrators. You need permission to create budgets on that billing account. If the command returns a permission error, create the same budget in the Cloud console under Billing, Budgets & alerts. Either way, the budget will not turn the cluster off.

## 6. APIs

`terraform/main.tf` enables these APIs during apply, and it does not disable them on destroy:

- `compute.googleapis.com`
- `container.googleapis.com`
- `iam.googleapis.com`
- `logging.googleapis.com`
- `monitoring.googleapis.com`

You can enable them now so the first apply spends less time waiting. **Free.**

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  iam.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project=PROJECT_ID
```

`gcloud services enable` turns those APIs on for the project. Enabling an API is not the same as creating a cluster.

Your user needs permission to create networks, GKE clusters, service accounts, and IAM bindings in `PROJECT_ID`. On a personal project, Owner is enough. You also need Billing Account User on the billing account if you linked it yourself.

## Next

Continue with [runbook-deploy.md](runbook-deploy.md). That is the first section that creates billable resources.
