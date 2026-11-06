cluster_name       = "fixture-cluster"
kubernetes_version = "1.32"

cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]

node_desired_size = 2
node_min_size     = 2
node_max_size     = 3

single_nat_gateway = false
