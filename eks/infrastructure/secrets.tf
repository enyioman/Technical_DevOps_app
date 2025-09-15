resource "aws_secretsmanager_secret" "db" {
  name = "${var.project}-db"
  tags = { Project = var.project }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = module.rds.db_instance_address
    port     = 5432
    dbname   = var.db_name
    username = var.db_username
    password = random_password.db.result
  })
}

output "db_secret_arn" { value = aws_secretsmanager_secret.db.arn }
