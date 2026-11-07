output "alb_dns_name" {
  description = "Public HTTPS entry point"
  value       = aws_lb.app.dns_name
}

output "app_instance_id" {
  description = "EC2 instance targeted by SSM deploy commands"
  value       = aws_instance.app.id
}

output "deployer_role_arn" {
  description = "Role assumed by the production deploy job through OIDC"
  value       = aws_iam_role.deployer.arn
}

output "tf_plan_role_arn" {
  description = "Read-only role assumed by validation/plan jobs through OIDC"
  value       = aws_iam_role.tf_plan.arn
}

output "db_secret_arns" {
  description = "Secrets Manager ARNs holding the generated DB master passwords"
  value       = { for k, db in aws_db_instance.db : k => db.master_user_secret[0].secret_arn }
}
