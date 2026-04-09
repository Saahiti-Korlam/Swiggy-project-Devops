
resource "aws_security_group" "My-Custom-Security-Group" {
  name        = "My-Custom-Security-Group"
  description = "Open 22,443,80,8080,9000"

  # Define a single ingress rule to allow traffic on all specified ports
  ingress = [
    for port in [22, 80, 443, 8080, 9000, 3000] : {
      description      = "TLS from VPC"
      from_port        = port
      to_port          = port
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "My-Custom-Security-Group"
  }
}


resource "aws_instance" "web" {
  ami                    = "ami-05d2d839d4f73aafb"
  instance_type          = "c7i-flex.large"
  key_name               = "sahi-ubuntu"
  vpc_security_group_ids = [aws_security_group.My-Custom-Security-Group.id]
  user_data              = templatefile("./resource.sh", {})

  tags = {
    Name = "My-Custom-EC2-Instance"
  }
  root_block_device {
    volume_size = 30
  }
}
