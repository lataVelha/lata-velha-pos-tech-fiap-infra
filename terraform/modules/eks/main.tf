locals {
  # O AWS Academy aplica uma SCP que nega ec2:DescribeInstances ao LabRole.
  # Sem o feature gate, o nodeadm consulta o PrivateDnsName via
  # DescribeInstances durante o boot e o node nunca entra no cluster
  # ("exceeded max wait time for InstanceCondition waiter"). Com
  # InstanceIdNodeName, o node usa o instance ID como nome e o bootstrap
  # nao depende mais da API do EC2. O restante do NodeConfig (cluster,
  # endpoint, CA, CIDR) continua sendo injetado pelo EKS e mesclado a este
  # user data.
  node_user_data = <<-EOT
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: application/node.eks.aws

apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  featureGates:
    InstanceIdNodeName: true

--==MYBOUNDARY==--
EOT
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.iam_role_arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode = "API"
  }
}

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.cluster_admin_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.cluster_admin_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}


resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"

  # Hop limit 2 permite que pods acessem o IMDS para obter
  # credenciais do LabRole via instance profile (padrão = 1, inacessível de pods).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  # Mesclado pelo EKS com o NodeConfig que ele injeta (cluster/endpoint/CA).
  user_data = base64encode(local.node_user_data)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = var.iam_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # Tags necessárias para o Cluster Autoscaler descobrir o Auto Scaling Group
  tags = {
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }
}
