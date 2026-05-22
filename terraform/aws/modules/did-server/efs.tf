# Shared filesystem holding did.json. Two consumers:
#   - did-server (this module): mounts RO at /issuer, serves /issuer/did.json
#   - seeder (modules/seeder): mounts RW at /well-known, writes did.json

resource "aws_efs_file_system" "this" {
  creation_token = "${var.name_prefix}-did-server"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [var.efs_security_group_id]
}

# Access point: pins POSIX uid/gid 101 (nginx user in nginx:alpine), so the
# seeder writes files that nginx can read. Path /well-known is created on
# first mount with mode 0755.
resource "aws_efs_access_point" "this" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 101
    gid = 101
  }

  root_directory {
    path = "/well-known"

    creation_info {
      owner_uid   = 101
      owner_gid   = 101
      permissions = "0755"
    }
  }
}
