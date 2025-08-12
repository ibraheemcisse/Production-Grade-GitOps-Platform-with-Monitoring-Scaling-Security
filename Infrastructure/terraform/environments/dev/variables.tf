
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "gitops-platform"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.27"
}

variable "application_names" {
  description = "List of application names for ECR repositories"
  type        = list(string)
  default     = [
    "frontend",
    "user-service",
    "product-service",
    "order-service",
    "notification-service"
  ]
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "gitops_platform"
}

variable "database_username" {
  description = "Database username"
  type        = string
  default     = "admin"
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
  default     = "changeme123!"
  
  validation {
    condition     = length(var.database_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

# Domain and DNS variables
variable "domain_name" {
  description = "Domain name for the platform"
  type        = string
  default     = "gitops-platform.example.com"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for SSL/TLS"
  type        = string
  default     = ""
}

# Monitoring and logging
variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
}

# Security settings
variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

variable "enable_cluster_encryption" {
  description = "Enable EKS cluster encryption"
  type        = bool
  default     = true
}

# Scaling configuration
variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "max_cluster_size" {
  description = "Maximum number of nodes in the cluster"
  type        = number
  default     = 20
}

# Backup and disaster recovery
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "enable_point_in_time_recovery" {
  description = "Enable point in time recovery for RDS"
  type        = bool
  default     = true
}

# Cost optimization
variable "use_spot_instances" {
  description = "Use spot instances for cost optimization"
  type        = bool
  default     = false
}

variable "node_group_instance_types" {
  description = "Instance types for EKS node groups"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

# Monitoring thresholds
variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold for scaling"
  type        = number
  default     = 70
}

variable "memory_utilization_threshold" {
  description = "Memory utilization threshold for scaling"
  type        = number
  default     = 80
}

# Security scanning
variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for ECR images"
  type        = bool
  default     = true
}

variable "vulnerability_scan_on_push" {
  description = "Scan images on push to ECR"
  type        = bool
  default     = true
}

# Network security
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_network_policy" {
  description = "Enable network policies"
  type        = bool
  default     = true
}

# GitOps configuration
variable "argocd_version" {
  description = "ArgoCD version to install"
  type        = string
  default     = "v2.8.0"
}

variable "git_repository_url" {
  description = "Git repository URL for GitOps"
  type        = string
  default     = ""
}

# Observability
variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana dashboards"
  type        = bool
  default     = true
}

variable "enable_jaeger" {
  description = "Enable Jaeger tracing"
  type        = bool
  default     = true
}

variable "enable_loki" {
  description = "Enable Loki logging"
  type        = bool
  default     = true
}

# Alerting
variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

# Load testing
variable "enable_load_testing" {
  description = "Enable load testing capabilities"
  type        = bool
  default     = true
}

variable "load_test_schedule" {
  description = "Cron schedule for automated load tests"
  type        = string
  default     = "0 2 * * 0" # Weekly on Sunday at 2 AM
}

# Chaos engineering
variable "enable_chaos_engineering" {
  description = "Enable chaos engineering tools"
  type        = bool
  default     = false
}

# Multi-environment support
variable "environments" {
  description = "List of environments to support"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

# Resource tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Compliance and governance
variable "enable_compliance_scanning" {
  description = "Enable compliance scanning"
  type        = bool
  default     = true
}

variable "compliance_frameworks" {
  description = "Compliance frameworks to check against"
  type        = list(string)
  default     = ["SOC2", "PCI-DSS"]
}