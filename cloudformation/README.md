## Prerequisites

AWS account + IAM permissions for CFN, EC2, ELBv2, RDS, S3, SNS, SSM, Secrets Manager, VPC.

AWS CLI v2 configured:

aws configure  # set default region/profile


An existing EC2 Key Pair name (not the .pem filename), e.g. sysuser1.

Files

stack.yaml — the template 

Option A — Deploy via AWS Console

Open CloudFormation → Create stack → With new resources.

Upload a template file → choose stack.yaml.

Fill parameters (examples):

Project=cognetiks-tech

KeyName=sysuser1

StaticBucketName and LogsBucketName must be globally unique.

DBPassword=<StrongPassword> (NoEcho)

On the final page, tick I acknowledge that AWS CloudFormation might create IAM resources.

Click Create stack and watch Events until CREATE_COMPLETE.

Copy values from the Outputs tab (e.g., AlbDnsName).

## Option B — Deploy via AWS CLI (recommended for reproducibility)

1) Set common variables (edit to your values)
```
cd Technical_DevOps_app/cloudformation

export REGION=us-east-1
export STACK_NAME=cognetiks-tech
export PROJECT=cognetiks-tech
export KEY_NAME=sysuser                    # key pair name, not .pem
export STATIC_BUCKET=cognetiks-tech-static-bucket
export LOGS_BUCKET=cognetiks-tech-logs-bucket
export DB_PASSWORD='ChangeMeToAStrongOne!'
export APP_REPO_URL='https://github.com/enyioman/Technical_DevOps_app.git'
```

2) Validate the template
```
aws cloudformation validate-template \
  --region "$REGION" \
  --template-body file://stack.yaml
```

3) Create the stack
```
aws cloudformation create-stack \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --template-body file://stack.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=Project,ParameterValue=$PROJECT \
    ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    ParameterKey=StaticBucketName,ParameterValue=$STATIC_BUCKET \
    ParameterKey=LogsBucketName,ParameterValue=$LOGS_BUCKET \
    ParameterKey=DBPassword,ParameterValue=$DB_PASSWORD \
    ParameterKey=AppRepoUrl,ParameterValue=$APP_REPO_URL \
    ParameterKey=CreateS3GatewayEndpoint,ParameterValue=true
```

4) Wait for completion (or tail events)
## Block until done
aws cloudformation wait stack-create-complete \
  --region "$REGION" --stack-name "$STACK_NAME"

## OR: simple zsh loop to watch recent events every 5s (no 'watch' needed)
```
while true; do
  clear; date
  aws cloudformation describe-stack-events --region "$REGION" --stack-name "$STACK_NAME" \
    --query 'reverse(Events[0:15].[Timestamp,ResourceStatus,LogicalResourceId,ResourceStatusReason])' \
    --output table
  sleep 5
done
```

## Fetch outputs
```
aws cloudformation describe-stacks \
  --region "$REGION" --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs" --output table

Examples to capture common outputs:
ALB_DNS=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
TG_ARN=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='TargetGroupArn'].OutputValue" --output text)
echo "ALB: http://$ALB_DNS"
```

## Health endpoint:
```curl -I "http://$ALB_DNS/healthz"```

## Target health:
```
aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].TargetHealth.State" --output text
```

## Updating the Stack

Edit stack.yaml, then:

```
aws cloudformation update-stack \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --template-body file://stack.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=Project,ParameterValue=$PROJECT \
    ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    ParameterKey=StaticBucketName,ParameterValue=$STATIC_BUCKET \
    ParameterKey=LogsBucketName,ParameterValue=$LOGS_BUCKET \
    ParameterKey=DBPassword,ParameterValue=$DB_PASSWORD \
    ParameterKey=AppRepoUrl,ParameterValue=$APP_REPO_URL \
    ParameterKey=CreateS3GatewayEndpoint,ParameterValue=true
```


## Deleting the Stack
```
aws cloudformation delete-stack --region "$REGION" --stack-name "$STACK_NAME"

aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$STACK_NAME"
```

Common Pitfalls & Fixes

S3 bucket names must be globally unique. Change StaticBucketName / LogsBucketName if creation fails.

KeyName is the key pair name, not the .pem filename.

IAM resources: include --capabilities CAPABILITY_NAMED_IAM or creation will fail.

Conditions/Fn::Equals error: define conditions at top-level and use !If in properties (e.g., MultiAZ: !If [ UseMultiAZ, true, false ]).

VPC Endpoint S3 condition “null” error: ensure Conditions: includes UseS3GatewayEndpoint, and resource uses Condition: UseS3GatewayEndpoint on one line.

Secrets Manager name conflict/scheduled deletion: either remove the fixed Name so CFN auto-names it, or restore/delete the old secret before re-creating.

Blank/HTTPS-only in browser: browse http://<AlbDnsName> first. If needed, add an ACM cert + HTTPS listener and (optional) HTTP→HTTPS redirect.

