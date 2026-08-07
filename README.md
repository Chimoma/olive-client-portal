# Olive & Olive — AWS Deployment

This project provisions the Olive & Olive client portal and data platform on AWS using Terraform. Every resource uses the `olive-` prefix.

**Scope note:** The client portal application (`../olive-app`) and its legacy source database (`olive-legacy-db-instance`, provisioned by `legacy-db.tf`) are included as part of this solution so the full path — application build, deployment, and database migration — is real and working end to end, not just infrastructure with nothing running on it.

---

## Folder Structure

```
terraform/
├── main.tf                    # Provider + backend
├── variables.tf                # Inputs
├── outputs.tf                  # Endpoints, URLs, ARNs
├── network.tf                  # VPC, public/private subnets, IGW, NAT
├── security.tf                 # KMS, security groups, IAM policies
├── secrets.tf                  # Secrets Manager (auto-generated DB password)
├── ecr.tf                      # Container registry
├── ecs.tf                      # Cluster, task definition, service
├── rds.tf                      # SQL Server Multi-AZ database (target)
├── redshift.tf                 # Analytics cluster
├── legacy-db.tf                # Legacy source database (pre-migration)
├── dms.tf                      # Migrates legacy-db into olive-db-instance
├── cicd.tf                     # GitHub connection, CodeBuild, CodeDeploy, CodePipeline, ALB
├── cloudwatch.tf               # Dashboard + alarms
└── terraform.tfvars.template   # Copy to terraform.tfvars and edit

olive-app/                      # Push into your GitHub repo (see Step 8)
├── src/
│   ├── OliveApp.csproj          # .NET 8 Web API project
│   ├── Program.cs               # /, /api/health/db, /api/customers endpoints
│   └── appsettings.json         # Local dev connection string
├── db/
│   ├── legacy-schema-seed.sql   # Seeds olive-legacy-db-instance
│   └── target-schema-seed.sql   # Optional: seed olive-db-instance directly
├── Dockerfile                   # Multi-stage build
├── buildspec.yml                # Tells CodeBuild how to build & push
├── appspec.yml                  # Tells CodeDeploy how to shift traffic
└── taskdef.json                 # ECS task definition template
```

---

## Prerequisites

```bash
terraform -version     # need v1.5+
aws --version
aws sts get-caller-identity   # confirms your credentials work
git --version
gh --version            # optional - GitHub CLI, useful for creating the repo
```

You'll also need a GitHub account with permission to create a repository and authorize the AWS Connector for GitHub app (done in Step 8).

---

## Step 1 — Create the Remote State Bucket

Terraform needs somewhere to store its state file before it can do anything else.

```bash
aws s3api create-bucket --bucket olive-terraform-state-533267120258 --region us-east-1
aws s3api put-bucket-versioning --bucket olive-terraform-state-533267120258 --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket olive-terraform-state-533267120258 --server-side-encryption-configuration '{
  "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
}'
```

> S3 bucket names must be globally unique across *all* AWS accounts, not just your own — that's why the account ID (`533267120258`) is appended to the name here. If you're deploying under a different AWS account, replace it with your own account ID (`aws sts get-caller-identity --query Account --output text`) in both this command and in `main.tf`'s `backend "s3"` block.
>
> If you're in a different region, update the `region` value in `main.tf`'s `backend "s3"` block to match.

---

## Step 2 — Configure Variables

```bash
cd terraform
cp terraform.tfvars.template terraform.tfvars
```

Open `terraform.tfvars` and adjust values if needed (region, instance sizes, environment name). You do **not** need to set a database password — Terraform generates a strong one automatically and stores it in Secrets Manager (`olive-db-secret`).

---

## Step 3 — Initialize Terraform

```bash
terraform init
```

This downloads the AWS and random providers and connects to your S3 backend.

---

## Step 4 — Validate and Plan

```bash
terraform fmt
terraform validate
terraform plan -out=olive.tfplan
```

Read the plan output. You should see roughly 55–65 resources to add, including:
- 1 VPC, 4 subnets, 1 NAT gateway, 2 route tables
- 1 KMS key, security groups, IAM roles with policies
- 1 ECR repo, 1 ECS cluster/service/task definition
- 1 RDS instance (Multi-AZ, target), 1 RDS instance (legacy source), 1 Redshift cluster
- 1 Secrets Manager secret
- DMS replication instance, endpoints, and task
- 1 GitHub connection, 1 CodeBuild project, 1 CodeDeploy app/group, 1 CodePipeline, 1 ALB
- 1 CloudWatch dashboard + 3 alarms

---

## Step 5 — Apply

```bash
terraform apply olive.tfplan
```

**This takes 25–35 minutes**, mostly waiting on RDS Multi-AZ provisioning, the legacy RDS instance, and the Redshift cluster.

---

## Step 6 — Capture the Outputs

```bash
terraform output
```

Note down:
- `olive_alb_dns_name` — where the application will be reachable once deployed
- `olive_github_connection_arn` — needed to authorize the GitHub connection (Step 8)
- `olive_ecr_repo_url` — the container registry
- `olive_legacy_db_endpoint` — the legacy source database endpoint
- `olive_cw_dashboard_url` — direct link to monitoring

---

## Step 7 — Confirm Core Infrastructure Is Healthy

```bash
aws rds describe-db-instances --db-instance-identifier olive-db-instance --query "DBInstances[0].DBInstanceStatus"
aws redshift describe-clusters --cluster-identifier olive-redshift-cluster --query "Clusters[0].ClusterStatus"
aws ecs describe-clusters --clusters olive-cluster --query "clusters[0].status"
```

All three should return `"available"` (RDS/Redshift) or `"ACTIVE"` (ECS).

---

## Step 8 — Create the GitHub Repo and Authorize the Connection

**8a. Create the repo on GitHub** (via the GitHub website or CLI) — e.g. `olive-app`, owned by whichever account/org you're using. Don't add a README or `.gitignore` from GitHub's side; you'll push existing content.

**8b. Set `github_repo` in `terraform.tfvars`** to match, in `owner/repo-name` format:
```hcl
github_repo   = "your-github-username/olive-app"
github_branch = "main"
```

**8c. Apply Terraform** so the connection resource exists:
```bash
cd terraform
terraform plan -out=olive.tfplan
terraform apply olive.tfplan
```

**8d. Authorize the connection manually.** AWS can create the *connection object*, but cannot complete the GitHub OAuth handshake on its own — this one step has to happen in the console:
1. Go to **Developer Tools → Settings → Connections** in the AWS Console (or search "CodeStar Connections" / "CodeConnections")
2. Find `olive-github-connection` — it will show status **Pending**
3. Click it → **Update pending connection** → follow the GitHub authorization prompt → install/authorize the AWS Connector for GitHub app on your repo (or your whole account)
4. Status should flip to **Available**

Confirm from the CLI once done:
```bash
aws codeconnections get-connection --connection-arn $(terraform output -raw olive_github_connection_arn) --query "Connection.ConnectionStatus"
```
Should return `"AVAILABLE"`.

**8e. Push the application code:**
```bash
cd ../olive-app
git init
git remote add origin https://github.com/your-github-username/olive-app.git
git add .
git commit -m "Initial commit: Olive client portal"
git branch -M main
git push -u origin main
```

Pushing to `main` automatically triggers `olive-pipeline` once the connection is authorized.

> **Note:** `/api/customers` will return an empty result (or a SQL error) until either `db/target-schema-seed.sql` is run directly against `olive-db-instance`, or the migration in Step 10 completes. The `/` and `/api/health/db` endpoints will work immediately once the app deploys.

---

## Step 9 — Watch the Pipeline Run

```bash
aws codepipeline get-pipeline-state --name olive-pipeline
```

Or watch it live in the console: **CodePipeline → olive-pipeline**. You'll see:
1. **Source** — pulls the code you just pushed
2. **Build** — CodeBuild builds the Docker image and pushes to `olive-ecr-repo`
3. **Deploy** — CodeDeploy shifts ECS traffic from blue → green

Once it's green, open `olive_alb_dns_name` in a browser — you should see the application running.

---

## Step 10 — Run the Database Migration

This seeds the legacy source database and migrates that data into `olive-db-instance` via DMS.

**10a. Seed the legacy database:**
```bash
cd ../terraform
terraform output -raw olive_legacy_db_endpoint
# then, using sqlcmd (or Azure Data Studio / SSMS pointed at that endpoint):
sqlcmd -S <endpoint-from-above> -U olive_admin -P <get-password-from-secrets-manager> \
  -i ../olive-app/db/legacy-schema-seed.sql
```
Get the password with:
```bash
aws secretsmanager get-secret-value --secret-id olive-db-secret --query SecretString --output text
```

**10b. Start the migration task:**
```bash
aws dms start-replication-task \
  --replication-task-arn $(aws dms describe-replication-tasks --query "ReplicationTasks[?ReplicationTaskIdentifier=='olive-dms-task'].ReplicationTaskArn" --output text) \
  --start-replication-task-type start-replication
```

**10c. Confirm the migrated data is queryable through the app:**
```bash
curl http://$(terraform output -raw olive_alb_dns_name)/api/customers
```
You should see the customer records that started in `olive-legacy-db-instance`, now served from `olive-db-instance`.

**Once cutover is verified:** edit `aws_dms_endpoint.olive_dms_source` in `dms.tf` if the source system changes, and run **AWS SCT** manually beforehand against its schema to convert anything that doesn't map directly (stored procedures, custom types) — SCT is a desktop tool and isn't something Terraform can drive. The legacy instance can then be decommissioned:
```bash
terraform destroy -target aws_db_instance.olive_legacy_db_instance
```

---

## Step 11 — Extending the Application

The included application (`olive-app/`) covers the client portal's core read path against the modernized database. To extend it:

1. Add project files, controllers, and views under `olive-app/src/` following the existing `Program.cs` structure.
2. Update `container_port` in `terraform.tfvars` if the app's listening port changes.
3. Update the SQL in `db/` to match schema changes.
4. Push changes to the GitHub repo — this triggers the pipeline automatically.

No infrastructure changes are needed for ongoing application changes — that's the benefit of having the pipeline already wired end-to-end.

---

## Step 12 — Tear Down

```bash
terraform destroy
```

> **Warning:** `olive_db_instance` has `deletion_protection = true`. You'll need to either remove that flag and re-apply first, or delete the RDS instance manually before `destroy` will succeed. Never run this against a production environment without a verified backup and an explicit change window.

---

## Security Notes

- All storage (RDS, Redshift, ECR, S3 artifacts, Secrets Manager) is encrypted with a single customer-managed KMS key (`olive-kms-key`) with automatic annual rotation enabled.
- The database password is never typed by a human — Terraform generates it and stores it only in Secrets Manager; the running ECS task reads it at runtime via IAM, not as a plaintext environment variable.
- ECS tasks and the target database sit in private subnets with no direct internet access; only outbound traffic is allowed via the NAT gateway.
- IAM roles are scoped per-service (ECS, CodeBuild, CodePipeline, CodeDeploy) rather than using one broad role — each can only do what its specific job requires.
- CodeDeploy uses blue/green deployment with automatic rollback on failure, so a bad deploy doesn't take down the running (green) service.

---

## What to Expand Before Production Sign-Off

- Add a WAF in front of the ALB and move to HTTPS with an ACM certificate.
- Add a second NAT gateway (one per AZ) for high availability — this configuration uses one to control cost.
- Replace `skip_final_snapshot = true` on Redshift with a real snapshot policy.
- Add automated testing stages to the pipeline (unit tests in CodeBuild, integration tests before the Deploy stage).
- Tighten the `iam:PassRole` statement in `olive-codepipeline-policy` to a specific role ARN rather than a wildcard, once the exact roles in play are finalized.
- Restrict `olive-legacy-db-sg`'s public ingress rule to known IP ranges, or remove it entirely once the initial data load is complete.
