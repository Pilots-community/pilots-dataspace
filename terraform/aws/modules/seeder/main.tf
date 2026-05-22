locals {
  issuer_did = "did:web:${var.root_domain}:issuer"

  # Python script that reads $ISSUER_KEY_PEM and writes did.json. Passed to
  # the container as a base64-encoded env var to avoid quoting nightmares;
  # entrypoint decodes it to /tmp/render.py before running.
  render_did_script = <<-PYTHON
    import base64, json, os
    from cryptography.hazmat.primitives import serialization

    pk = serialization.load_pem_private_key(
        os.environ['ISSUER_KEY_PEM'].encode(), password=None,
    )
    nums = pk.public_key().public_numbers()

    def b64e(n, length):
        return base64.urlsafe_b64encode(n.to_bytes(length, 'big')).rstrip(b'=').decode()

    issuer_did = os.environ['ISSUER_DID']
    doc = {
        '@context': [
            'https://www.w3.org/ns/did/v1',
            'https://w3id.org/security/suites/jws-2020/v1',
        ],
        'id': issuer_did,
        'verificationMethod': [{
            'id': f'{issuer_did}#issuer-key-1',
            'type': 'JsonWebKey2020',
            'controller': issuer_did,
            'publicKeyJwk': {
                'kty': 'EC', 'crv': 'P-256',
                'x': b64e(nums.x, 32),
                'y': b64e(nums.y, 32),
                'kid': 'issuer-key-1',
            },
        }],
        'authentication': [f'{issuer_did}#issuer-key-1'],
        'assertionMethod': [f'{issuer_did}#issuer-key-1'],
    }
    with open('/well-known/did.json', 'w') as f:
        json.dump(doc, f, indent=2)
    print('Wrote did.json for', issuer_did)
  PYTHON
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-seeder"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  volume {
    name = "did-content"

    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = var.efs_access_point_id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name      = "seeder"
    image     = "python:3.12-slim"
    essential = true
    environment = [
      { name = "ISSUER_DID", value = local.issuer_did },
      { name = "RENDER_SCRIPT_B64", value = base64encode(local.render_did_script) },
    ]
    secrets = [
      { name = "ISSUER_KEY_PEM", valueFrom = var.issuer_private_key_secret_arn },
    ]
    mountPoints = [
      { sourceVolume = "did-content", containerPath = "/well-known", readOnly = false },
    ]
    command = [
      "sh", "-c",
      "echo \"$RENDER_SCRIPT_B64\" | base64 -d > /tmp/render.py && pip install --quiet --no-cache-dir cryptography==43.0.1 && python /tmp/render.py",
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.region
        awslogs-stream-prefix = "seeder"
      }
    }
  }])
}
