## Prerequisites

- **AWS CLI v2**, **Terraform ≥ 1.6**, **jq**
- An AWS user/role that can create IAM, EC2, ELB, SSM, CloudWatch, Secrets Manager
- **Secrets Manager** secret containing your DB connection JSON (example below)
- (Optional) S3 bucket for Django static assets

## Secrets Manager format (expected by bootstrap)

Create (or reuse) a secret with this JSON structure:

```json
{
  "dbname": "appdb",
  "engine": "postgres",
  "host": "your-db.abcdefgh.us-east-1.rds.amazonaws.com",
  "password": "SuperSecret!",
  "port": 5432,
  "username": "appuser"
}
```

Pass the expected json through Terraform. Example `terraform.tfvars`

```hcl

project         = "cognetiks-tech"
region          = "us-east-1"

app_repo_url    = "https://github.com/cognetiks/Technical_DevOps_app.git"
app_branch      = "main"
wsgi_module     = "mysite.wsgi:application"

secret_name     = "cognetiks-tech-db"
static_bucket   = "cognetiks-tech-static"

instance_type   = "t3.small"
desired_capacity = 2
min_size        = 2
max_size        = 5

alert_email     = "you@example.com"
```

## Deployment

From the Terraform directory that contains your modules (infrastructure/ or root of the stack):

```
cd Technical_DevOps_app/aws-infrastructure

export AWS_REGION=us-east-1

terraform init
terraform validate
terraform plan
terraform apply 
```

## Destroy

```terraform destroy```