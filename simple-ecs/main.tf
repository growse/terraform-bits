provider "aws" {
  region  = "eu-west-1"
  profile = "personal"
}

module "vpc" {
  source                             = "terraform-aws-modules/vpc/aws"
  name                               = "test-cluster-vpc"
  cidr                               = "10.1.0.0/16"
  azs                                = ["eu-west-1a", "eu-west-1b"]
  private_subnets                    = ["10.1.1.0/24", "10.1.2.0/24"]
  public_subnets                     = ["10.1.11.0/24", "10.1.12.0/24"]
  database_subnets                   = ["10.1.21.0/24", "10.1.22.0/24"]
  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_ipv6                                    = true
  assign_ipv6_address_on_creation                = true
  private_subnet_assign_ipv6_address_on_creation = false
  public_subnet_ipv6_prefixes                    = [0, 1]
  private_subnet_ipv6_prefixes                   = [2, 3]
  database_subnet_ipv6_prefixes                  = [4, 5]
}


module "alb_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = "test-web-server-alb"
  description = "Security group for ALB, forwarding to ECS web-server with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

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
      name_prefix      = "pref-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
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

module "ecs_security_group" {
  source              = "terraform-aws-modules/security-group/aws//modules/http-80"
  name                = "container security group"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = module.vpc.public_subnets_cidr_blocks
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
  task_role_arn            = aws_iam_role.ecs-task-role.arn
  cpu                      = 1024
  memory                   = 2048
  container_definitions = jsonencode([
    {
      name                   = "simple-web"
      image                  = "quay.io/jitesoft/nginx:latest"
      cpu                    = 1024
      memory                 = 2048
      essential              = true
      readonlyRootFilesystem = false
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
          containerPort = 80
          hostPort      = 80
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
    container_port   = 80
  }

  network_configuration {
    security_groups  = [module.ecs_security_group.security_group_id]
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

  name        = "test rds-security-group"
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
