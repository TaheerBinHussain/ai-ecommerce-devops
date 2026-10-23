environment      = "dev"
aws_region       = "ap-south-1"
instance_type    = "t3.medium"
root_volume_size = 30
vpc_cidr         = "10.20.0.0/16"
# Replace with your public IP: curl -s https://checkip.amazonaws.com
admin_cidrs = ["203.0.113.10/32"]
