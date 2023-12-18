resource "aws_vpc" "NewYorkMets_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "vpc-proyecto"
  }
}

# Definición de las Subnets
resource "aws_subnet" "public_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.NewYorkMets_vpc.id
  cidr_block              = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true
  # Otras configuraciones de la subred pública

  tags = {
    Name = "SubredPública${count.index + 1}"
  }
}

resource "aws_route_table" "NewYorkMets_route_table" {
  vpc_id = aws_vpc.NewYorkMets_vpc.id
  tags = {
    Name = "RouteTableProject"
  }
}

# Asocia la tabla de enrutamiento a las subnets públicas
resource "aws_route_table_association" "NewYorkMets_Association_public_subnet" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.NewYorkMets_route_table.id
}

resource "aws_route" "aws_route_prueba" {
  route_table_id = aws_route_table.NewYorkMets_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.NewYorkMets_Internet_Gateway.id
}

# Define un Internet Gateway
resource "aws_internet_gateway" "NewYorkMets_Internet_Gateway" {
  vpc_id = aws_vpc.NewYorkMets_vpc.id
  tags = {
    Name = "MyInternetGateway"
  }
}

# Definición de un grupo de seguridad
resource "aws_security_group" "NewYorkMets_Security_Group" {
  name        = "MySecurityGroup"
  description = "Security Group for the project"
  vpc_id      = aws_vpc.NewYorkMets_vpc.id

  # Primera regla de tráfico de entrada
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/16"]
  }

  # Segunda regla de tráfico de entrada
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Definicion del cluster de ECS

resource "aws_ecs_cluster" "NewYorkMets_Cluster" {
  name = "Cluster-Proyecto"
}

# Creación del rol de IAM para las tareas de ECS
resource "aws_iam_role" "NewYorkMets_Excecution_role" {
  name = "NewYorkMets_Excecution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_pull_image" {
  role       = aws_iam_role.NewYorkMets_Excecution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  # Puedes usar la política "AmazonEC2ContainerRegistryFullAccess" para permisos completos
}

resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.NewYorkMets_Excecution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_access" {
  role       = aws_iam_role.NewYorkMets_Excecution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

# Definición de la tarea de ECS
resource "aws_ecs_task_definition" "NewYorkMets_Task_Definition" {
  family                   = "Task-NewYorkMets-1"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.NewYorkMets_Excecution_role.arn

  cpu    = "1024"
  memory = "2048"

  # definir la configuracion de los contenedores
  container_definitions = jsonencode([
    {
      Name  = "my-container"
      image = "" 
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

#Definicion del servicio de ECS
resource "aws_ecs_service" "NewYorkMets_ECS_Service" {
  name            = "My-ecs-service"
  cluster         = aws_ecs_cluster.NewYorkMets_Cluster.id
  task_definition = aws_ecs_task_definition.NewYorkMets_Task_Definition.arn
  launch_type     = "FARGATE"
  desired_count   = 2
  load_balancer {
    target_group_arn = aws_lb_target_group.NewYorkMets_Target_Group.arn
    container_name   = "my-container"
    container_port   = 80
  }
  network_configuration {
    subnets          = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
    security_groups  = [aws_security_group.NewYorkMets_Security_Group.id]
    assign_public_ip = true
  }
}

#Balanceador de carga
resource "aws_lb" "NewYorkMets_lb" {
  name               = "my-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.NewYorkMets_Security_Group.id]
  subnets            = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]

}

#Grupos de destino para el balanceador de carga
resource "aws_lb_target_group" "NewYorkMets_Target_Group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.NewYorkMets_vpc.id
}

#Listerner Load Balancer
resource "aws_lb_listener" "NewYorkMets_Listener_lb" {
  load_balancer_arn = aws_lb.NewYorkMets_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.NewYorkMets_Target_Group.arn
  }
 
}