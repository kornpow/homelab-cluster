# Cluster SG
resource "aws_security_group" "cluster_internal" {
  name        = "cluster_internal traffic"
  description = "Allow cluster_internal traffic"
  vpc_id      = var.vpc_id

  tags = {
    Name = "cluster-internal"
  }
}

resource "aws_security_group_rule" "traefik_dashboard" {
  type              = "ingress"
  from_port         = 9000
  to_port           = 9000
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  security_group_id = aws_security_group.cluster_internal.id
}

# Dev SG
resource "aws_security_group" "dev_access" {
  name        = "dev_access traffic"
  description = "Allow dev_access traffic"
  vpc_id      = var.vpc_id

  tags = {
    Name = "dev-access"
  }
}

resource "aws_security_group_rule" "dev_home_fullaccess" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["${var.dev_home_ip}/32"]
  security_group_id = aws_security_group.dev_access.id
}


# Traefik Ingress
resource "aws_security_group" "traefik_ingress" {
  name        = "traefik_ingress"
  description = "Allow traefik_ingress traffic"
  vpc_id      = var.vpc_id

  tags = {
    Name = "internet-to-traefik"
  }
}

resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.traefik_ingress.id
}

resource "aws_security_group_rule" "allow_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.traefik_ingress.id
}


resource "aws_security_group" "internet_access" {
  name        = "internet_access"
  description = "Allow egress internet_access traffic"
  vpc_id      = var.vpc_id

  tags = {
    Name = "internet-access"
  }
}

resource "aws_security_group_rule" "internet_access_everywhere" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.internet_access.id
}

resource "aws_iam_role" "cluster_instance_role" {
  name = "cluster_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::190928636648:user/skorn"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  })
}

# resource "aws_iam_role" "developer_role" {
#   name = "dev_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Sid    = ""
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       },
#     ]
#   })

#   tags = {
#     Name = "dev-role"
#   }
# }

resource "aws_iam_policy" "cluster_ecr_login_policy" {
  name        = "cluster_ecr_login_policy"
  path        = "/"
  description = "Allows a cronjob in k3s cluster to refresh ECR token"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:ListImages",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_full_access" {
  role       = aws_iam_role.cluster_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_token_refresh" {
  role       = aws_iam_role.cluster_instance_role.name
  policy_arn = aws_iam_policy.cluster_ecr_login_policy.arn
}

# Secrets Manager policy for syncing secrets to k3s
resource "aws_iam_policy" "cluster_secrets_manager_policy" {
  name        = "cluster_secrets_manager_policy"
  path        = "/"
  description = "Allows k3s cluster to read secrets from AWS Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.cloudflare_tunnel_token.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_secrets_manager" {
  role       = aws_iam_role.cluster_instance_role.name
  policy_arn = aws_iam_policy.cluster_secrets_manager_policy.arn
}

# Cloudflare Tunnel Token Secret
# NOTE: After creation, edit the secret value via AWS Console:
# https://us-west-2.console.aws.amazon.com/secretsmanager/secret?name=cloudflare-tunnel-token
resource "aws_secretsmanager_secret" "cloudflare_tunnel_token" {
  name                    = "cloudflare-tunnel-token"
  description             = "Cloudflare Tunnel token for k3s cluster"
  recovery_window_in_days = 7

  tags = {
    Name = "cloudflare-tunnel-token"
  }
}

# Create initial placeholder version - user will edit this via AWS Console
resource "aws_secretsmanager_secret_version" "cloudflare_tunnel_token" {
  secret_id     = aws_secretsmanager_secret.cloudflare_tunnel_token.id
  secret_string = "PLACEHOLDER_EDIT_VIA_AWS_CONSOLE"
}

resource "aws_iam_instance_profile" "cluster_instance_profile" {
  name = "cluster_instance_profile"
  role = aws_iam_role.cluster_instance_role.name
}