
resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cider
  tags = {
    Name      = var.vpc_name
    terraform = true
  }
}

resource "aws_subnet" "public_subnet" {
  for_each          = var.public_subnet
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cider, 8, each.value)
  availability_zone = each.key
  tags = {
    Name      = "public-subnet-${each.key}"
    terraform = true
  }
}

resource "aws_subnet" "private_subnet" {
  for_each          = var.private_subnet
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cider, 8, each.value)
  availability_zone = each.key
  tags = {
    Name      = "private-subnet-${each.key}"
    terraform = true
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    type = "public"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    type = "private"
  }
}

resource "aws_route_table_association" "subnet_wep_pub" {
  for_each       = aws_subnet.public_subnet
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "subnet_wep_priv" {
  for_each       = aws_subnet.private_subnet
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_eip" "eip" {
  tags = {
    Name = "Nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  depends_on    = [aws_subnet.public_subnet]
  allocation_id = aws_eip.eip.id
  subnet_id     = values(aws_subnet.public_subnet)[0].id
  tags = {
    Name = "project_nat_gateway"
  }
}

resource "aws_key_pair" "my_key" {
  public_key = file(pathexpand("~/.ssh/id_rsa.pub"))
  key_name   = "instance-key"
}

resource "aws_security_group" "webSG" {
  name   = "webSG"
  vpc_id = aws_vpc.main_vpc.id
  dynamic "ingress" {
    for_each = var.allowed_ports
    iterator = port
    content {
      from_port   = port.value
      to_port     = port.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.me_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet["us-east-1a"].id
  availability_zone      = "us-east-1a"
  vpc_security_group_ids = [aws_security_group.webSG.id]
  key_name               = aws_key_pair.my_key.key_name
  root_block_device {
    encrypted = true
  }
  user_data = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start httpd
        systemctl enable httpd
        echo "This is server *1* in AWS Region US-EAST-1 in AZ US-EAST-1A " > /var/www/html/index.html
        EOF
  tags = {
    Name = "WEB_instance"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.me_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet["us-east-1b"].id
  vpc_security_group_ids = [aws_security_group.webSG.id]
  availability_zone      = "us-east-1b"
  key_name               = aws_key_pair.my_key.key_name
  root_block_device {
    encrypted = true
  }
  user_data = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start httpd
        systemctl enable httpd
        echo "This is server *1* in AWS Region US-EAST-1 in AZ US-EAST-1B " > /var/www/html/index.html
        EOF
  tags = {
    Name = "APP_instance"
  }
}

resource "aws_lb_target_group" "webTG" {
  name       = "webTG"
  port       = 80
  protocol   = "HTTP"
  vpc_id     = aws_vpc.main_vpc.id
  depends_on = [aws_vpc.main_vpc]
}

resource "aws_lb_target_group_attachment" "attach_web" {
  target_group_arn = aws_lb_target_group.webTG.arn
  target_id        = aws_instance.web.id
  port             = 80
  depends_on       = [aws_instance.web]
}

resource "aws_lb_target_group_attachment" "attach_app" {
  target_group_arn = aws_lb_target_group.webTG.arn
  target_id        = aws_instance.app.id
  port             = 80
  depends_on       = [aws_instance.app]
}

resource "aws_lb" "project_lb" {
  name               = "project-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lbSG.id]
  subnets            = [aws_subnet.public_subnet["us-east-1a"].id, aws_subnet.public_subnet["us-east-1b"].id]
  tags = {
    Environment = "production"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.project_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webTG.arn
  }
}

resource "aws_security_group" "lbSG" {
  name   = "lbSG"
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.webSG.id]
  }
}

resource "aws_launch_template" "Scaled_instance" {
  name_prefix     = "Scaled_launch_instance"
  image_id        = data.aws_ami.me_ami.id
  instance_type   = var.instance_type
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ec2_auto_scaling" {
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.Scaled_instance.name
  vpc_zone_identifier  = [aws_subnet.private_subnet["us-east-1a"].id, aws_subnet.private_subnet["us-east-1b"].id]
}

resource "aws_autoscaling_attachment" "asg_target" {
  autoscaling_group_name = aws_autoscaling_group.ec2_auto_scaling.id
  lb_target_group_arn    = aws_lb_target_group.webTG.arn
}

resource "aws_db_subnet_group" "db_subnet" {
  name       = "rds-db-subnet"
  subnet_ids = [aws_subnet.private_subnet["us-east-1a"].id, aws_subnet.private_subnet["us-east-1b"].id]
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "security group for RDS database"
  vpc_id      = aws_vpc.main_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.webSG.id]
  }
}

resource "aws_db_instance" "rds_instance" {
  allocated_storage      = 20
  identifier             = "rds-terraform"
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0.27"
  instance_class         = "db.t2.micro"
  db_name                = "project_rds"
  username               = "dolfined"
  password               = "dolfined"
  publicly_accessible    = false
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  tags = {
    Name = "ExampleRDSServerInstance"
  }
}