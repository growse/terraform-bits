provider "aws" {
  region = "eu-west-1"
}

resource "aws_key_pair" "keypair" {
  key_name   = "keypair"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII39VYdZwNXVFbIveDgj3rmAaqDdGlEvmyx96ODUOhE3"
}


resource "aws_spot_instance_request" "gradle-build-mirakle" {
  ami                  = "ami-01ebd2b650c37e4d6" # amd Debian 11
  spot_price           = "0.90"
  spot_type            = "one-time"
  instance_type        = "c6i.8xlarge"
  key_name             = aws_key_pair.keypair.id
  ipv6_address_count   = 1
  subnet_id            = aws_subnet.subnet.id
  security_groups      = [aws_security_group.mill-ssh.id]
  user_data            = file("provision.sh")
  wait_for_fulfillment = true
  timeouts {
    create = "1m"
  }
  root_block_device {
    volume_size = 24
  }
  tags                 = {
    Name = "Gradle Build Mirakle"
  }
  depends_on           = [aws_internet_gateway.gw]
}

output "DNS_name" {
  value = aws_spot_instance_request.gradle-build-mirakle.public_dns
}
