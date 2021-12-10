resource "aws_vpc" "gradle-build-env" {
  assign_generated_ipv6_cidr_block = true
  cidr_block                       = "10.0.0.0/16"
  enable_dns_hostnames             = true
  enable_dns_support               = true
}

resource "aws_subnet" "subnet" {
  # creates a subnet
  cidr_block                      = cidrsubnet(aws_vpc.gradle-build-env.cidr_block, 3, 1)
  vpc_id                          = aws_vpc.gradle-build-env.id
  map_public_ip_on_launch         = true
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.gradle-build-env.ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.gradle-build-env.id
}

resource "aws_default_route_table" "eu-west-2" {
  default_route_table_id = aws_vpc.gradle-build-env.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "eu-west-2" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_default_route_table.eu-west-2.id
}

resource "aws_security_group" "mill-ssh" {
  name   = "allow-ssh-sg"
  vpc_id = aws_vpc.gradle-build-env.id

  ingress {
    cidr_blocks      = [
      "81.2.103.168/32"
    ]
    ipv6_cidr_blocks = [
      "2001:8b0:c8f:e8b0::/64"
    ]

    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
