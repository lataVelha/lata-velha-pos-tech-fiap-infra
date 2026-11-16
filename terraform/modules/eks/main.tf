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

  # O role dos nodes ganha um access entry tipo EC2 (username
  # system:node:{{SessionName}}), que e o tipo exigido quando o node name e o
  # instance ID (feature gate InstanceIdNodeName). Como um principal so pode
  # ter um access entry, ele nao pode aparecer tambem como admin.
  admin_arns = [for arn in var.cluster_admin_arns : arn if arn != var.iam_role_arn]
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
  for_each = toset(local.admin_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

# EKS managed node groups criam por padrao um access entry EC2_LINUX
# (username system:node:{{EC2PrivateDNSName}}). Com InstanceIdNodeName o node
# se registra como instance ID, entao o username precisa ser
# system:node:{{SessionName}} (type EC2), senao o kubelet autentica mas o
# Node Authorizer rejeita o registro ("can only access ... its own Node").
resource "aws_eks_access_entry" "nodes" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.iam_role_arn
  type          = "EC2"

  depends_on = [aws_eks_cluster.this]
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

# O nodeadm usa InstanceIdNodeName (ver locals.node_user_data), então o nome do
# Node no Kubernetes é o ID da instância (i-...), não o private DNS name.
# O access entry que o EKS cria sozinho para managed node groups é do tipo
# EC2_LINUX, cujo username é fixo em system:node:{{EC2PrivateDNSName}} — com
# InstanceIdNodeName isso não bate com o nome do Node e o kubelet não consegue
# se registrar ("node 'ip-...' cannot read 'i-...', only its own Node object").
# O tipo EC2 mapeia para system:node:{{SessionName}}, que no instance profile é
# o ID da instância. Criamos a entrada ANTES do node group para que o EKS a
# reaproveite em vez de criar a EC2_LINUX.
resource "aws_eks_access_entry" "nodes" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.iam_role_arn
  type          = "EC2"
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

  # Garante o access entry EC2 (InstanceIdNodeName) antes de os nodes subirem.
  depends_on = [aws_eks_access_entry.nodes]
}
