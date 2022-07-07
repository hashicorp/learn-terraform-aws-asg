output "lb_endpoint" {
  value = "https://${aws_lb.terramino.dns_name}"
}

output "application_endpoint" {
  value = "https://${aws_lb.terramino.dns_name}/index.php"
}

output "asg_name" {
  value = aws_autoscaling_group.terramino.name
}

//output values make information about your infrastructure available on the command line
// output is similar to return 