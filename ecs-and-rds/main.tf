provider "aws" {
  region  = "eu-west-1"
  profile = "personal"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "test-cluster-vpc"
  cidr   = "10.1.0.0/16"

  azs              = ["eu-west-1a", "eu-west-1b"]
  private_subnets  = ["10.1.1.0/24", "10.1.2.0/24"]
  public_subnets   = ["10.1.11.0/24", "10.1.12.0/24"]
  database_subnets = ["10.1.21.0/24", "10.1.22.0/24"]

  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  manage_default_security_group = true
  default_security_group_name   = "Default sg"

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = false
  single_nat_gateway = false

  enable_ipv6                                    = true
  assign_ipv6_address_on_creation                = true
  private_subnet_assign_ipv6_address_on_creation = false
  public_subnet_ipv6_prefixes                    = [0, 1]
  private_subnet_ipv6_prefixes                   = [2, 3]
  database_subnet_ipv6_prefixes                  = [4, 5]
}


module "alb_sg" {
  source              = "terraform-aws-modules/security-group/aws//modules/http-80"
  name                = "ALB public security group"
  description         = "Security group for ALB, allowing everyone access in on HTTP"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = ["0.0.0.0/0"] # Let the whole world access our ALB
}

module "alb" {
  source             = "terraform-aws-modules/alb/aws"
  version            = "~> 6.0"
  name               = "test-alb"
  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.alb_sg.security_group_id]
  target_groups = [
    {
      name_prefix      = "test-"
      backend_protocol = "HTTP"
      backend_port     = var.container_port
      target_type      = "ip"
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/healthz"
        port                = "traffic-port"
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }
      targets = {
      }
    }
  ]
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]
}

module "ecr_sg" {
  source              = "terraform-aws-modules/security-group/aws//modules/https-443"
  name                = "ECR private security group"
  description         = "Security group for ECR allowing access from private subnet on HTTPS"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = module.vpc.private_subnets_cidr_blocks
}

module "vpc_endpoints" {
  source             = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.ecr_sg.security_group_id]
  endpoints = {
    ecr_api = {
      tags                = { "Name" : "ECR API" }
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    },
    ecr_dkr = {
      tags                = { "Name" : "ECR Docker Registry" }
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets

    },
    s3 = {
      tags            = { "Name" : "S3 Gateway" }
      description     = "Required by Fargate 1.4.0 to pull images"
      service         = "s3"
      service_type    = "Gateway"
      subnet_ids      = module.vpc.private_subnets
      route_table_ids = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
    }
    cloudwatch_logs = {
      tags                = { "Name" : "Cloudwatch Logging Gateway" }
      service             = "logs"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
  }
}

module "ecs_sg_inbound" {
  source              = "terraform-aws-modules/security-group/aws"
  name                = "ECS container security group inbound"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = module.vpc.public_subnets_cidr_blocks
  // ECS should allow traffic in on the container port
  ingress_with_cidr_blocks = [
    {
      to_port     = var.container_port
      from_port   = var.container_port
      protocol    = "tcp"
      description = "Container port ${var.container_port}"
    }
  ]
}

module "ecs_sg_outbound_to_s3" {
  source = "terraform-aws-modules/security-group/aws"
  name   = "ECS container security group outbound to VPC endpoints"
  vpc_id = module.vpc.vpc_id
  egress_prefix_list_ids = [
    module.vpc_endpoints.endpoints.s3.prefix_list_id,
  ]
  // ECS needs to be able to access things on the private subnet over port 443
  egress_cidr_blocks      = module.vpc.private_subnets_cidr_blocks
  egress_ipv6_cidr_blocks = []
  egress_rules            = ["https-443-tcp"]
}

module "ecs_sg_outbound_to_rds" {
  source                  = "terraform-aws-modules/security-group/aws"
  name                    = "ECS container security group outbound to RDS"
  vpc_id                  = module.vpc.vpc_id
  egress_cidr_blocks      = module.vpc.database_subnets_cidr_blocks
  egress_ipv6_cidr_blocks = []
  egress_rules            = ["postgresql-tcp"]
}
module "ecs" {
  source             = "terraform-aws-modules/ecs/aws"
  name               = "test-cluster"
  container_insights = true
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
    }
  ]
}

resource "aws_ecs_task_definition" "simple-web" {
  family                   = "simple-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  cpu                      = 1024
  memory                   = 2048
  container_definitions = jsonencode([
    {
      name                   = "simple-web"
      image                  = "760367158108.dkr.ecr.eu-west-1.amazonaws.com/test-repository:latest"
      cpu                    = 1024
      memory                 = 2048
      essential              = true
      readonlyRootFilesystem = false
      environment = [
        { "name" : "DATABASE_HOST", "value" : "${module.rds_postgres.db_instance_address}" },
        { "name" : "DATABASE_PORT", "value" : "${tostring(module.rds_postgres.db_instance_port)}" },
        { "name" : "DATABASE_USERNAME", "value" : "${tostring(module.rds_postgres.db_instance_username)}" },
        { "name" : "DATABASE_PASSWORD", "value" : "${tostring(module.rds_postgres.db_instance_password)}" },
        { "name" : "DATABASE_NAME", "value" : "${tostring(module.rds_postgres.db_instance_name)}" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.main.name
          awslogs-stream-prefix = "ecs"
          awslogs-region        = "eu-west-1"
        }
      }
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
        }
      ]
    }
  ])
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/test-task"
  retention_in_days = 1
}

resource "aws_ecs_service" "simple-web" {
  name            = "simple-web"
  cluster         = module.ecs.ecs_cluster_id
  task_definition = aws_ecs_task_definition.simple-web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = module.alb.target_group_arns[0]
    container_name   = "simple-web"
    container_port   = var.container_port
  }

  network_configuration {
    security_groups = [
      module.ecs_sg_inbound.security_group_id,
      module.ecs_sg_outbound_to_rds.security_group_id,
      module.ecs_sg_outbound_to_s3.security_group_id
    ]
    subnets          = module.vpc.private_subnets
    assign_public_ip = false
  }
}

module "ecr" {
  source                            = "terraform-aws-modules/ecr/aws"
  repository_read_access_arns       = [aws_iam_role.ecs_task_execution_role.arn]
  repository_read_write_access_arns = ["arn:aws:iam::760367158108:user/growse"]
  repository_name                   = "test-repository"
  repository_image_tag_mutability   = "MUTABLE"

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 2 images",
        selection = {
          tagStatus = "any",

          countType   = "imageCountMoreThan",
          countNumber = 2
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}

module "rds_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "Test RDS SG"
  description = "Complete PostgreSQL example security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]
}

module "rds_postgres" {
  source     = "terraform-aws-modules/rds/aws"
  identifier = "rd-test"

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "14.2"
  family               = "postgres14" # DB parameter group
  major_engine_version = "14"         # DB option group
  instance_class       = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 30

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name  = "testDatabase"
  username = "testUser"
  port     = 5432

  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.rds_sg.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled          = false
  performance_insights_retention_period = 1
  create_monitoring_role                = true
  monitoring_interval                   = 60
  monitoring_role_name                  = "example-monitoring-role-name"
  monitoring_role_description           = "Description for monitoring role"
}


// A role for the fargate task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "test-ecs-task-execution-role"
  assume_role_policy = file("iam-ecs-assumerole-policy.json")
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

// A role that the task will run as
resource "aws_iam_role" "ecs_task_role" {
  name               = "test-ecs-task-role"
  assume_role_policy = file("iam-ecs-assumerole-policy.json")
}

// The policy for the ECS task role
resource "aws_iam_policy" "ecs_task_role_policy" {
  name        = "test-ecs-task-role-policy"
  description = "Policy that allows access to some things"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "*"
        ],
        "Resource" : "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "ecs_task_role-policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_role_policy.arn
}
