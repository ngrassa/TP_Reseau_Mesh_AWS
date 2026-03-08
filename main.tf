#============================================================================
# main.tf — Infrastructure AWS pour TP Mesh OLSR
# Auteur : Pr Noureddine GRASSA — ISET Sousse
# Région : us-east-1 (Virginie du Nord)
#============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ── Variables ──────────────────────────────────────────────────────────────

variable "region" {
  default = "us-east-1"
}

variable "key_name" {
  default = "vockey"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "node_count" {
  default = 5
}

variable "project" {
  default = "tp-mesh-olsr"
}

# ── AMI Ubuntu 22.04 (dernière version) ───────────────────────────────────

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Réseau ─────────────────────────────────────────────────────────────────

resource "aws_vpc" "mesh" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project}-vpc"
    Project = var.project
  }
}

resource "aws_subnet" "mesh" {
  vpc_id                  = aws_vpc.mesh.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project}-subnet"
    Project = var.project
  }
}

resource "aws_internet_gateway" "mesh" {
  vpc_id = aws_vpc.mesh.id

  tags = {
    Name    = "${var.project}-igw"
    Project = var.project
  }
}

resource "aws_route_table" "mesh" {
  vpc_id = aws_vpc.mesh.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mesh.id
  }

  tags = {
    Name    = "${var.project}-rt"
    Project = var.project
  }
}

resource "aws_route_table_association" "mesh" {
  subnet_id      = aws_subnet.mesh.id
  route_table_id = aws_route_table.mesh.id
}

# ── Security Group ─────────────────────────────────────────────────────────

resource "aws_security_group" "mesh" {
  name        = "${var.project}-sg"
  description = "Security group pour TP Mesh OLSR"
  vpc_id      = aws_vpc.mesh.id

  # SSH depuis partout (pour le TP)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Tout le trafic interne au subnet mesh
  ingress {
    description = "Trafic interne mesh"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.1.0/24"]
  }

  # Sortie internet (pour apt-get)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-sg"
    Project = var.project
  }
}

# ── Instances EC2 (les 5 nœuds mesh) ──────────────────────────────────────

resource "aws_instance" "mesh_node" {
  count = var.node_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.mesh.id
  vpc_security_group_ids = [aws_security_group.mesh.id]
  private_ip             = "10.0.1.${count.index + 11}"

  # Désactiver la vérification source/destination (nécessaire pour le routage mesh)
  source_dest_check = false

  tags = {
    Name    = "mesh-node${count.index + 1}"
    Project = var.project
  }
}

# ── Provisioning OLSR via remote-exec ─────────────────────────────────────

resource "null_resource" "provision_mesh" {
  count = var.node_count

  depends_on = [aws_instance.mesh_node]

  # Se reconnecter si l'instance change
  triggers = {
    instance_id = aws_instance.mesh_node[count.index].id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/labuser.pem")
    host        = aws_instance.mesh_node[count.index].public_ip
    timeout     = "3m"
  }

  # Copier le script de provisioning
  provisioner "file" {
    source      = "provision.sh"
    destination = "/tmp/provision.sh"
  }

  # Exécuter le provisioning
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/provision.sh",
      "sudo bash /tmp/provision.sh 10.0.1.${count.index + 11}"
    ]
  }
}

# ── Outputs ────────────────────────────────────────────────────────────────

output "mesh_nodes" {
  description = "Informations de connexion des nœuds mesh"
  value = {
    for i, instance in aws_instance.mesh_node : "mesh-node${i + 1}" => {
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
      ssh        = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${instance.public_ip}"
    }
  }
}

output "summary" {
  description = "Résumé de l'infrastructure"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════╗
    ║     TP Mesh OLSR — Infrastructure déployée      ║
    ╠══════════════════════════════════════════════════╣
    ║  VPC      : ${aws_vpc.mesh.id}                  
    ║  Subnet   : ${aws_subnet.mesh.id}               
    ║  AMI      : ${data.aws_ami.ubuntu.id}            
    ║  Nœuds    : ${var.node_count}                    
    ╚══════════════════════════════════════════════════╝

    Commandes utiles :
      terraform output mesh_nodes
      terraform destroy
  EOT
}
