terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# 1. VPC creation
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "my-free-vpc" }
}

# 2. Internet Gateway (for free)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = { Name = "my-igw" }
}

# 3. Public Subnet (for web-server)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true # Set public IP
  tags = { Name = "public-subnet-1a" }
}

# 4. Route Table - from subnet to internet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-route-table" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 5. Private Subnets (for PostgreSQL)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1a"
  tags = { Name = "private-subnet-1a" }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1b" # Must have different AZ
  tags = { Name = "private-subnet-1b" }
}

# --- 6. Security Groups ---
# Security group for the web server (access from the Internet)
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In a production environment we will limit it to only your local IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for DB (accepts communication only from the web server)
resource "aws_security_group" "db_sg" {
  name        = "db_sg"
  description = "Allow Postgres from Web SG"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 7. EC2 Web Server ---
# Pulling the latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro" # Free Tier
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = "my-aws-key" # key name we created earlier
  
  tags = { Name = "Django-Web-Server" }
}

# --- 8. RDS PostgreSQL ---
# Connecting the two private subnets to the DB
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "main_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

resource "aws_db_instance" "postgres_db" {
  identifier             = "free-tier-db"
  allocated_storage      = 20 # free
  engine                 = "postgres"
  engine_version         = "15" 
  instance_class         = "db.t3.micro" # Free Tier
  username               = "dbadmin"
  password               = "SuperSecretPassword123!" # Should be in Secret in prod 
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true # Critical so we can easily delete the database without paying for backups
  publicly_accessible    = false 
}

# Create a bucket in S3 to store static files (free in Free Tier up to 5GB)
resource "aws_s3_bucket" "static_files" {
  bucket_prefix = "noam-django-static-" # Name must be unique
}

# Output: Printing the IP address of the server so we can connect the CI to it
output "ec2_public_ip" {
  description = "The public IP address of the web server"
  value       = aws_instance.web.public_ip
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_db_instance.postgres_db.address 
}