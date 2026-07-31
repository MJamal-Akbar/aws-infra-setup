###############################################################################
# main.tf  —  Single-file VPC design for testing
# Creates: VPC, 1 public subnet, 1 private subnet, IGW, route tables, 1 EC2
###############################################################################

# ---------------------------------------------------------------------------
# PROVIDER — tells Terraform we're using AWS and which region
# ---------------------------------------------------------------------------
provider "aws" {
  region = "us-east-1" # change to your closest region (e.g. me-central-1 for Middle East)
}

# ---------------------------------------------------------------------------
# VPC — your network boundary (172.16.0.0/16 gives you 65k addresses)
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_support   = true # lets instances resolve DNS
  enable_dns_hostnames = true # gives instances DNS names

  tags = {
    Name = "jml-vpc-git"
  }
}

# ---------------------------------------------------------------------------
# PUBLIC SUBNET — 172.16.1.0/24, has a route to the internet
# map_public_ip_on_launch = true auto-assigns public IPs to EC2 here
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "git-public-subnet"
  }
}

# ---------------------------------------------------------------------------
# PRIVATE SUBNET — 172.16.2.0/24, NO direct internet route (secure)
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "git-private-subnet"
  }
}

# ---------------------------------------------------------------------------
# INTERNET GATEWAY — the door between your VPC and the internet
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "git-igw"
  }
}

# ---------------------------------------------------------------------------
# PUBLIC ROUTE TABLE — sends all outbound traffic (0.0.0.0/0) to the IGW
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "git-public-rt"
  }
}

# Associate the public route table WITH the public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# PRIVATE ROUTE TABLE — local-only routing, no internet path
# (AWS adds the local VPC route automatically; we add no 0.0.0.0/0)
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "git-private-rt"
  }
}

# Associate the private route table WITH the private subnet
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# SECURITY GROUP — your firewall. Allows SSH in, all traffic out.
# NOTE: 0.0.0.0/0 on SSH means the whole internet can reach port 22.
# Fine for a quick test; lock it to your own IP for anything real.
# ---------------------------------------------------------------------------
resource "aws_security_group" "ec2_sg" {
  name        = "git-ec2-sg"
  description = "Allow SSH inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # ⚠️ replace with "YOUR.IP.ADDRESS/32" ideally
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 = all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "git-ec2-sg"
  }
}

# ---------------------------------------------------------------------------
# AMI LOOKUP — dynamically find the latest Amazon Linux 2 image
# (best practice: never hardcode AMI IDs, they differ per region & go stale)
# ---------------------------------------------------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ---------------------------------------------------------------------------
# EC2 INSTANCE — placed in the PUBLIC subnet so you can SSH to it
# t3.micro is free-tier eligible
# ---------------------------------------------------------------------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name = "git-ec2-instance"
  }
}

# ---------------------------------------------------------------------------
# OUTPUTS — printed after apply, so you get the useful values instantly
# ---------------------------------------------------------------------------
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}