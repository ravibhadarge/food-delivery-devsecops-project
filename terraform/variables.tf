# ═══════════════════════════════════════════════════════════════════
# Variables — EKS Auto Mode (no node config needed!)
# ═══════════════════════════════════════════════════════════════════

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "ravibhadarge"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "Food-Delivery"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "food-delivery-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.34"
}

# ─────────────────────────────────────────────────────────────────
# Bastion Server
# ─────────────────────────────────────────────────────────────────
variable "bastion_instance_type" {
  description = "EC2 instance type for bastion (t3.medium for SonarQube)"
  type        = string
  default     = "c7i-flex.large"
}
