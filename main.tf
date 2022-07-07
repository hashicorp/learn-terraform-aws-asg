// provider block configures the specified provider. 
provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      hashicorp-learn = "aws-asg"
    }
  }
}
//the data block querys for the availibility zones in the region that has been selected
data "aws_availability_zones" "available" {
  state = "available"
}

//vpc module using your cidr blocks chosen earlier. 
// turn this into a reusable module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"

  name = "main-vpc"
  cidr = "10.0.0.0/16" 

  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}
//azs = slice(data.aws_availability_zones.azs.names, 0,2)
//public_subnets = var.public_subnets
// slice function takes a list (in this case a list of availibilty zone names) and it slices off a piece of that 
// list starting with 0 and ending with 2 



// data source, this is the ami that i chose to use on aws
// data sources are kind of like an api. you are fetching data, returning it and using it in your configuraton.
data "aws_ami" "amazon-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-ebs"]
  }
}

// each resource block describes one or more infrastructure objects
// resource blocks documents the syntax for declaring resources
resource "aws_launch_configuration" "terramino" {
  name_prefix     = "learn-terraform-aws-asg-"
  image_id        = data.aws_ami.amazon-linux.id
  instance_type   = "t2.micro"
  user_data       = file("user-data.sh")
  security_groups = [aws_security_group.terramino_instance.id]

  lifecycle {
    create_before_destroy = true
  }
}

// this monitors my aplicaion and automatically adjusts capacity. it handles potential traffic spikes
// to scale up when needed and down when needed as defined
//this defines the minimum and maximum number of instances defined in a group
// the launch configuration to use for each group
// this configuration references the public subnets created by the vpc module above
resource "aws_autoscaling_group" "terramino" {
  name                 = "terramino"
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.terramino.name
  vpc_zone_identifier  = module.vpc.public_subnets

  tag {
    key                 = "Name"
    value               = "HashiCorp Learn ASG - Terramino"
    propagate_at_launch = true
  }
}

// LB load balancer - distributes trffic across an instance

resource "aws_lb" "terramino" {
  name               = "learn-asg-terramino-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.terramino_lb.id]
  subnets            = module.vpc.public_subnets
}
// the listener is forwarding requests (http requests) to a target group
// target group specifies a list of destinations the LB can forward a request to
resource "aws_lb_listener" "terramino" {
  load_balancer_arn = aws_lb.terramino.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.terramino.arn
  }
}

//defining the target group
resource "aws_lb_target_group" "terramino" {
  name     = "learn-asg-terramino"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

//links the autoscaling-group with the target group 
//allows aws to add and remove instances from the target group over their lifecycle 
resource "aws_autoscaling_attachment" "terramino" {
  autoscaling_group_name = aws_autoscaling_group.terramino.id
  alb_target_group_arn   = aws_lb_target_group.terramino.arn
}

// security groups ( the instance level firewall) who can come in and who can leave
// this defines two security groups, one for the EC2 instance and the other for the LB
//
//eagress means exiting the cloud, in gress means entering the cloud
//defines who does and who doesn't have access
// in this case it allows all traffic leaving the cloud
// inbound traffic is limited ensuring that only requests from the load balancer will reach the instance

resource "aws_security_group" "terramino_instance" {
  name = "learn-asg-terramino-instance"
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.terramino_lb.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.terramino_lb.id]
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "terramino_lb" {
  name = "learn-asg-terramino-lb"
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

  vpc_id = module.vpc.vpc_id
}
