# Fixture for CI: a small, mostly-healthy EKS repo the doctor audits.
# Deliberate gaps (so CI can assert WARN detection): no PodDisruptionBudget
# (CLU-07) and no ApplicationSet (ARG-04). Everything else should PASS.
variable "cluster_name" {
  type    = string
  default = "fixture-cluster"
}

variable "kubernetes_version" {
  type    = string
  default = "1.32"
}

variable "cluster_endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["203.0.113.10/32"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "single_nat_gateway" {
  type    = bool
  default = false
}
