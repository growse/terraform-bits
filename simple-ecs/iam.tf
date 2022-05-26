// A role for the fargate task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "test-ecs_task_execution_role"
  assume_role_policy = file("iam-ecs-assumerole-policy.json")
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

// A role that the task will run as
resource "aws_iam_role" "ecs-task-role" {
  name               = "test-ecs-task-role"
  assume_role_policy = file("iam-ecs-assumerole-policy.json")
}

// The policy for the ECS task role
resource "aws_iam_policy" "ecs-task-role-policy" {
  name        = "test-ecs-task-policy"
  description = "Policy that allows access to some things"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket"
        ],
        "Resource" : "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "ecs-task-role-policy-attachment" {
  role       = aws_iam_role.ecs-task-role.name
  policy_arn = aws_iam_policy.ecs-task-role-policy.arn
}
