variable "project" {}
variable "static_bucket" {}
variable "logs_bucket" {}
variable "region" {}

resource "aws_s3_bucket" "static" { bucket = var.static_bucket }
resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# Optional: bucket policy to allow the app role to write (we scope via IAM later)

resource "aws_s3_bucket" "logs" { bucket = var.logs_bucket }
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Minimal ALB logging policy (use AWS doc snippet for your Region)
# See: "Enable access logs for your Application Load Balancer". :contentReference[oaicite:3]{index=3}
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AWSLogDeliveryWrite",
      Effect    = "Allow",
      Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" },
      Action    = ["s3:PutObject"],
      Resource  = "${aws_s3_bucket.logs.arn}/*",
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.me.account_id }
      }
    }]
  })
}
data "aws_caller_identity" "me" {}

output "static_bucket_arn" { value = aws_s3_bucket.static.arn }
