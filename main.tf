//aws provider

provider "aws" {
  region                  = "ap-south-1"
  profile                 = "default"
}

// VPC 

resource "aws_vpc" "VPC_Deployment" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "VPC_Deployment"
  }
}

//Public _SUBNET

resource "aws_subnet" "public_sub" {
  depends_on = [aws_vpc.VPC_Deployment]
  vpc_id     = aws_vpc.VPC_Deployment.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a" 
  map_public_ip_on_launch = true
  tags = {
    Name = "public_sub"
  }
}

//Private Subnet 

resource "aws_subnet" "private_sub" {
  vpc_id     = aws_vpc.VPC_Deployment.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1a" 
  
  tags = {
    Name = "private_sub"
  }
}




// Internet GateWay

resource "aws_internet_gateway" "IG_VPC_Deployment" {

  vpc_id = aws_vpc.VPC_Deployment.id

  tags = {
    Name = "IG_VPC_Deployment"
  }
}

// Route Table

resource "aws_route_table" "RT_IG_public" {
  vpc_id = aws_vpc.VPC_Deployment.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IG_VPC_Deployment.id
  }

  tags = {
    Name = "RT_IG_public"
  }
}

//Assosiation Route Table with Subnet Public

resource "aws_route_table_association" "Assosiate_IG_RT" {
  subnet_id     = aws_subnet.public_sub.id
  route_table_id = aws_route_table.RT_IG_public.id
}


//Security Group for Wordpress Instance
resource "aws_security_group" "SG_WordPress" {
  depends_on = [aws_vpc.VPC_Deployment]
  name        = "wordpress_http_ssh"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.VPC_Deployment.id
  revoke_rules_on_delete = "true"
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress{
    description = "SSH for VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security_group_WordPress"
  }
}

//Secutiy Group for MySQL instance

resource "aws_security_group" "SG_MySQL" {
  depends_on = [aws_vpc.VPC_Deployment]
  name        = "mysql_ssh"
  description = "Allow DB and SSH inbound traffic"
  vpc_id      = aws_vpc.VPC_Deployment.id
  revoke_rules_on_delete = "true"
  ingress {
    description = "DB from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress{
    description = "SSH for VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


//Launch EC2 instance with MySQL
resource "aws_instance" "MySQL" {
  depends_on = [
    aws_security_group.SG_MySQL,
  ]
  ami           = "ami-052c08d70def0ac62"
  subnet_id   = aws_subnet.private_sub.id
  instance_type = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.SG_MySQL.id}"]
  //security_groups = ["${aws_security_group.SG_MySQL.name}"]
  key_name = "keypair_docker_webserver"
}


//Launch EC2 instance with Wordpress
resource "aws_instance" "WordPress" {
  depends_on = [
    aws_security_group.SG_WordPress,
    aws_instance.MySQL
  ]
  ami           = "ami-052c08d70def0ac62"
  subnet_id   = aws_subnet.public_sub.id
  instance_type = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.SG_WordPress.id}"]
  //security_groups = ["${aws_security_group.SG_WordPress.name}"]
  key_name = "keypair_docker_webserver"
  tags = {
    name = "WordPress"
  }
}


resource "null_resource" "configure_remote1" {
  depends_on = [ aws_instance.WordPress ]
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("./keypair_docker_webserver.pem")
    host        = aws_instance.WordPress.public_ip
  }
  provisioner "remote-exec" {
  inline = [
    "sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo" ,
    "sudo yum install docker-ce -y --nobest",
    "sudo systemctl start docker",
    "sudo systemctl enable docker",
    "sudo docker run -dit -p 80:80 --name wordpress wordpress:5.1.1-php7.3-apache" 
  ]
}
}



resource "null_resource" "nulllocal1"  { 
  depends_on = [ null_resource.configure_remote1 ]
  provisioner "local-exec" {
	    command = "start chrome http://${aws_instance.WordPress.public_ip}"
 	}
}


output "myos_ip" {
    value = aws_instance.WordPress.public_ip
}



