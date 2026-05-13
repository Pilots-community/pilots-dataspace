resource "aws_efs_file_system" "pilots" {
  creation_token = "pilots-connector-${var.environment}"

  tags = {
    Name        = "pilots-connector-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_efs_access_point" "postgres_data" {
  file_system_id = aws_efs_file_system.pilots.id

  posix_user {
    gid = 70
    uid = 70
  }

  root_directory {
    path = "/postgres-data"
    creation_info {
      owner_gid   = 70
      owner_uid   = 70
      permissions = "0700"
    }
  }
}

resource "aws_efs_mount_target" "pilots" {
  for_each = toset(data.aws_subnets.default.ids)

  file_system_id  = aws_efs_file_system.pilots.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_sg.id]
}
