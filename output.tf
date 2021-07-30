output "reader_endpoint" {
  value       = join("", aws_rds_cluster.default.*.reader_endpoint)
  description = "A read-only endpoint for the Aurora cluster, automatically load-balanced across replicas"
}

output "master_host" {
  value       = module.dns_master.hostname
  description = "DB Master hostname"
}

output "cluster_resource_id" {
  value       = join("", aws_rds_cluster.default.*.cluster_resource_id)
  description = "The region-unique, immutable identifie of the cluster"
}

output "cluster_security_groups" {
  value       = coalescelist(aws_rds_cluster.default.*.vpc_security_group_ids, [""])
  description = "Default RDS cluster security groups"
}

output "reader_endpoint" {
  value       = join("", aws_rds_cluster.default.*.reader_endpoint)
  description = "A read-only endpoint for the Aurora cluster, automatically load-balanced across replicas"
}


output "database_name" {
  value       = var.db_name
  description = "Database name"
}

output "master_username" {
  value       = join("", aws_rds_cluster.default.*.master_username)
  description = "Username for the master DB user"
}
