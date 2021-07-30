
# ----------------------------------------------------------------------------------------------------------------------
# MODULES / RESOURCES
# ----------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {
  count = var.account_id == "" ? 1 : 0
}

resource "aws_security_group" "default" {
  count       = var.create && var.allowed_cidr_blocks != [] ? 1 : 0
  name        = local.module_prefix
  description = "Allow inbound traffic from Security Groups and CIDRs"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = var.security_groups
  }

  ingress {
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_db_subnet_group" "default" {
  count       = var.create && var.db_subnet_group_name == null ? 1 : 0
  name        = local.module_prefix
  description = "Allowed subnets for DB cluster instances"
  subnet_ids  = var.subnets
  tags        = local.tags
}

resource "aws_rds_cluster_parameter_group" "default" {
  count       = var.create && var.db_cluster_parameter_group_name == null ? 1 : 0
  name        = local.module_prefix
  description = "DB cluster parameter group"
  family      = var.cluster_family

  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      apply_method = lookup(parameter.value, "apply_method", null)
      name         = parameter.value.name
      value        = parameter.value.value
    }
  }

  tags = local.tags
}

resource "aws_db_parameter_group" "default" {
  count       = var.create && var.engine_mode != "serverless" ? 1 : 0
  name        = local.module_prefix
  description = "DB instance parameter group"
  family      = var.cluster_family

  dynamic "parameter" {
    for_each = var.instance_parameters
    content {
      apply_method = lookup(parameter.value, "apply_method", null)
      name         = parameter.value.name
      value        = parameter.value.value
    }
  }

  tags = local.tags
}

module "rds_creds" {
  source = "git::https://github.com/gravicore/terraform-gravicore-modules.git//aws/parameters?ref=0.20.0"
  providers = {
    aws = aws
  }
  create = var.create && var.admin_password == "" ? true : false

  namespace   = var.namespace
  environment = var.environment
  stage       = var.stage
  tags        = local.tags
  parameters = [
    "/${local.stage_prefix}/${var.name}-password",
    "/${local.stage_prefix}/${var.name}-username",
  ]
}

resource "aws_rds_cluster" "default" {
  count                               = var.create ? 1 : 0
  cluster_identifier                  = local.module_prefix
  database_name                       = var.db_name
  master_username                     = coalesce(var.admin_user, lookup(lookup(module.rds_creds.parameters, "/${local.stage_prefix}/${var.name}-username", {}), "value", ""))
  master_password                     = coalesce(var.admin_password, lookup(lookup(module.rds_creds.parameters, "/${local.stage_prefix}/${var.name}-password", {}), "value", ""))
  backup_retention_period             = var.retention_period
  preferred_backup_window             = var.backup_window
  copy_tags_to_snapshot               = var.copy_tags_to_snapshot
  final_snapshot_identifier           = var.cluster_identifier == "" ? lower(local.module_prefix) : lower(var.cluster_identifier)
  skip_final_snapshot                 = var.skip_final_snapshot
  apply_immediately                   = var.apply_immediately
  storage_encrypted                   = var.storage_encrypted
  kms_key_id                          = var.kms_key_arn
  source_region                       = var.source_region
  snapshot_identifier                 = var.snapshot_identifier
  vpc_security_group_ids              = compact(flatten([join("", aws_security_group.default.*.id), var.vpc_security_group_ids]))
  preferred_maintenance_window        = var.maintenance_window
  db_subnet_group_name                = coalesce(join("", aws_db_subnet_group.default.*.name), var.db_subnet_group_name)
  db_cluster_parameter_group_name     = coalesce(join("", aws_rds_cluster_parameter_group.default.*.name), var.db_cluster_parameter_group_name)
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  tags                                = local.tags
  engine                              = var.engine
  engine_version                      = var.engine_version
  engine_mode                         = var.engine_mode
  global_cluster_identifier           = var.global_cluster_identifier
  iam_roles                           = var.iam_roles
  backtrack_window                    = var.backtrack_window
  enable_http_endpoint                = var.engine_mode == "serverless" && var.enable_http_endpoint ? true : false

  dynamic "scaling_configuration" {
    for_each = var.scaling_configuration
    content {
      auto_pause               = lookup(scaling_configuration.value, "auto_pause", null)
      max_capacity             = lookup(scaling_configuration.value, "max_capacity", null)
      min_capacity             = lookup(scaling_configuration.value, "min_capacity", null)
      seconds_until_auto_pause = lookup(scaling_configuration.value, "seconds_until_auto_pause", null)
      timeout_action           = lookup(scaling_configuration.value, "timeout_action", null)
    }
  }

  dynamic "timeouts" {
    for_each = var.timeouts_configuration
    content {
      create = lookup(timeouts.value, "create", "120m")
      update = lookup(timeouts.value, "update", "120m")
      delete = lookup(timeouts.value, "delete", "120m")
    }
  }

  replication_source_identifier   = var.replication_source_identifier
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  deletion_protection             = var.deletion_protection
}

locals {
  cluster_dns_name = var.cluster_dns_name != "" ? var.cluster_dns_name : local.module_prefix
}

module "dns_master" {
  source  = "git::https://github.com/cloudposse/terraform-aws-route53-cluster-hostname.git?ref=tags/0.3.0"
  enabled = var.create && length(var.zone_id) > 0 ? true : false
  name    = local.cluster_dns_name
  zone_id = var.zone_id
  records = coalescelist(aws_rds_cluster.default.*.endpoint, [""])
}

# ----------------------------------------------------------------------------------------------------------------------
# OUTPUTS
# ----------------------------------------------------------------------------------------------------------------------

resource "aws_ssm_parameter" "aurora_sls_pg_username" {
  count       = var.create && var.admin_user != "" ? 1 : 0
  name        = "/${local.stage_prefix}/${var.name}-username"
  description = format("%s %s", var.desc_prefix, "Username for the master DB user")
  tags        = var.tags

  type  = "String"
  value = join("", aws_rds_cluster.default.*.master_username)
}

resource "aws_ssm_parameter" "aurora_sls_pg_password" {
  count       = var.create && var.admin_password != "" ? 1 : 0
  name        = "/${local.stage_prefix}/${var.name}-password"
  description = format("%s %s", var.desc_prefix, "Password for the master DB user")
  tags        = var.tags

  type  = "String"
  value = var.admin_password
}

output "cluster_identifier" {
  value       = join("", aws_rds_cluster.default.*.cluster_identifier)
  description = "Cluster Identifier"
}

output "arn" {
  value       = join("", aws_rds_cluster.default.*.arn)
  description = "Amazon Resource Name (ARN) of cluster"
}

output "endpoint" {
  value       = join("", aws_rds_cluster.default.*.endpoint)
  description = "The DNS address of the RDS instance"
}

resource "aws_ssm_parameter" "aurora_sls_pg_endpoint" {
  count       = var.create ? 1 : 0
  name        = "/${local.stage_prefix}/${var.name}-endpoint"
  description = format("%s %s", var.desc_prefix, "The DNS address of the RDS instance")
  tags        = var.tags

  type  = "String"
  value = join("", aws_rds_cluster.default.*.endpoint)
}

