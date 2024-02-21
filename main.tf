resource "aws_ecr_repository" "helloworld" {
  name = "helloworld"
}
# Output to display the URL of the ECR repository
output "ecr_repo_url" {
  value = aws_ecr_repository.helloworld.repository_url
}

# Docker image build and push configuration
resource "null_resource" "docker_build_push" {
  triggers = {
    ecr_repo_url = aws_ecr_repository.helloworld.repository_url
  }

  # Command to build and push the Docker image to the ECR repository
  provisioner "local-exec" {
    command = <<-EOT
      docker build -t ${aws_ecr_repository.helloworld.repository_url}:latest .
      $(aws ecr get-login --no-include-email --region us-east-1)
      aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.helloworld.repository_url}

      docker push ${aws_ecr_repository.helloworld.repository_url}:latest
    EOT
  }
}
resource "aws_ecs_cluster" "helloworld" {
  name = "helloworld"
}

resource "aws_ecs_task_definition" "helloworld" {
  family                   = "helloworld"
  container_definitions    = <<DEFINITION
[
  {
    "name": "helloworld",
    "image": "${aws_ecr_repository.helloworld.repository_url}",
    "essential": true,
    "portMappings": [
      {
        "containerPort": 3000,
        "hostPort": 3000
      }
    ],
    "memory": 512,
    "cpu": 256
  }
]
DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "helloworld" {
  name            = "helloworld"
  cluster         = "${aws_ecs_cluster.helloworld.id}"
  task_definition = "${aws_ecs_task_definition.helloworld.arn}"
  launch_type     = "FARGATE"
  desired_count   = 1

 # load_balancer {
 #   target_group_arn = "${aws_lb_target_group.target_group.arn}"
 #   container_name   = "${aws_ecs_task_definition.helloworld.family}"
 #   container_port   = 3000
 # }

  network_configuration {
    subnets          = [aws_subnet.public_subnet.id]
    assign_public_ip = true
    security_groups  = ["${aws_security_group.service_security_group.id}"]
  }
}

resource "aws_security_group" "service_security_group" {
  vpc_id = aws_vpc.my_vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# Define the VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create an Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
}

# Define a public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.1.0/24"
}

# Associate the public subnet with a route table
resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_vpc.my_vpc.default_route_table_id
}

# Configure the route table with a default route to the Internet Gateway
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.my_vpc.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_igw.id
}

#output "app_url" {
#  value = aws_alb.application_load_balancer.dns_name
# }

