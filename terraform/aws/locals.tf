locals {
  private_key_pem = trimspace(file("${path.module}/../../config/certs/private-key.pem"))
  public_key_pem  = trimspace(file("${path.module}/../../config/certs/public-key.pem"))
  issuer_did_json = trimspace(file("${path.module}/../../deployment/assets/issuer/did.json"))
  nginx_conf      = trimspace(file("${path.module}/../../deployment/nginx.conf"))

  postgres_init_sql = trimspace(file("${path.module}/../../config/docker/postgres-connector-init.sql"))

  identityhub_config = replace(
    replace(
      replace(
        replace(
          replace(
            file("${path.module}/../../config/docker/identityhub-connector.properties"),
            "edc.hostname=identityhub",
            "edc.hostname=${var.root_domain}"
          ),
          "edc.iam.did.web.use.https=false",
          "edc.iam.did.web.use.https=true"
        ),
        "did:web:identityhub%3A7093",
        "did:web:${var.root_domain}%3A7093"
      ),
      "jdbc:postgresql://postgres:5432/identityhub",
      "jdbc:postgresql://postgres.pilots.internal:5432/identityhub"
    ),
    "http://vault:8200",
    "http://vault.pilots.internal:8200"
  )

  controlplane_config = replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                file("${path.module}/../../config/docker/controlplane-connector.properties"),
                "edc.participant.id=did:web:identityhub%3A7093",
                "edc.participant.id=did:web:${var.root_domain}%3A7093"
              ),
              "edc.hostname=controlplane",
              "edc.hostname=${var.root_domain}"
            ),
            "edc.dsp.callback.address=http://controlplane:19194/protocol",
            "edc.dsp.callback.address=https://${var.root_domain}/dsp/protocol"
          ),
          "did:web:identityhub%3A7093",
          "did:web:${var.root_domain}%3A7093"
        ),
        "edc.iam.did.web.use.https=false",
        "edc.iam.did.web.use.https=true"
      ),
      "http://identityhub:7096/api/sts/token",
      "http://identityhub.pilots.internal:7096/api/sts/token"
    ),
    "jdbc:postgresql://postgres:5432/controlplane",
    "jdbc:postgresql://postgres.pilots.internal:5432/controlplane"
  )

  controlplane_config_final = replace(
    local.controlplane_config,
    "http://vault:8200",
    "http://vault.pilots.internal:8200"
  )

  dataplane_config = replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              file("${path.module}/../../config/docker/dataplane-connector.properties"),
              "edc.hostname=dataplane",
              "edc.hostname=${var.root_domain}"
            ),
            "http://controlplane:19192/control/v1/dataplanes",
            "http://controlplane.pilots.internal:19192/control/v1/dataplanes"
          ),
          "edc.transfer.proxy.token.signer.privatekey.path=/app/certs/private-key.pem",
          "edc.transfer.proxy.token.signer.privatekey.path=/tmp/private-key.pem"
        ),
        "edc.transfer.proxy.token.verifier.publickey.path=/app/certs/public-key.pem",
        "edc.transfer.proxy.token.verifier.publickey.path=/tmp/public-key.pem"
      ),
      "edc.dataplane.api.public.baseurl=http://dataplane:38185/public",
      "edc.dataplane.api.public.baseurl=https://${var.root_domain}/data/public"
    ),
    "jdbc:postgresql://postgres:5432/dataplane",
    "jdbc:postgresql://postgres.pilots.internal:5432/dataplane"
  )

  dataplane_config_final = replace(
    local.dataplane_config,
    "http://vault:8200",
    "http://vault.pilots.internal:8200"
  )

  services = {
    postgres = {
      image          = "postgres:16-alpine"
      container_ports = [5432]
      cpu            = 256
      memory         = 512
      environment = [
        { name = "POSTGRES_USER", value = "edc" },
        { name = "POSTGRES_PASSWORD", value = "edc" },
        { name = "POSTGRES_DB", value = "controlplane" },
        { name = "POSTGRES_INIT_SQL", value = local.postgres_init_sql }
      ]
      command = [
        "sh",
        "-c",
        "printf '%s\n' \"$POSTGRES_INIT_SQL\" > /docker-entrypoint-initdb.d/init.sql && exec docker-entrypoint.sh postgres"
      ]
      mount_points = [
        { sourceVolume = "postgres-data", containerPath = "/var/lib/postgresql/data", readOnly = false }
      ]
    }
    vault = {
      image          = "hashicorp/vault:1.15"
      container_ports = [8200]
      cpu            = 256
      memory         = 512
      environment    = []
      command        = ["vault", "server", "-dev", "-dev-root-token-id=root-token", "-dev-listen-address=0.0.0.0:8200"]
      mount_points   = []
    }
    did-server = {
      image          = "nginx:alpine"
      container_ports = [9876]
      cpu            = 256
      memory         = 512
      environment = [
        { name = "NGINX_CONF", value = local.nginx_conf },
        { name = "ISSUER_DID_JSON", value = local.issuer_did_json }
      ]
      command = [
        "sh",
        "-c",
        "mkdir -p /usr/share/nginx/html/.well-known && printf '%s\n' \"$NGINX_CONF\" > /etc/nginx/conf.d/default.conf && printf '%s\n' \"$ISSUER_DID_JSON\" > /usr/share/nginx/html/.well-known/did.json && exec nginx -g 'daemon off;'"
      ]
      mount_points = []
    }
    dashboard = {
      image          = "ghcr.io/pilots-community/pilots-dataspace/dashboard:${var.image_tag}"
      container_ports = [80]
      cpu            = var.ecs_cpu
      memory         = var.ecs_memory
      environment = [
        { name = "CP_HOST", value = "controlplane.pilots.internal" },
        { name = "DP_HOST", value = "dataplane.pilots.internal" },
        { name = "IH_HOST", value = "identityhub.pilots.internal" }
      ]
      command        = null
      mount_points   = []
    }
    identityhub = {
      image          = "ghcr.io/pilots-community/pilots-dataspace/identityhub:${var.image_tag}"
      container_ports = [7090, 7091, 7092, 7093, 7095, 7096]
      cpu            = var.ecs_cpu
      memory         = var.ecs_memory
      environment = [
        { name = "IDENTITYHUB_CONFIG", value = local.identityhub_config }
      ]
      command = [
        "sh",
        "-c",
        "printf '%s\n' \"$IDENTITYHUB_CONFIG\" > /tmp/identityhub-connector.properties && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/tmp/identityhub-connector.properties -jar identityhub.jar"
      ]
      mount_points = []
    }
    controlplane = {
      image          = "ghcr.io/pilots-community/pilots-dataspace/controlplane:${var.image_tag}"
      container_ports = [18181, 19192, 19193, 19194]
      cpu            = var.ecs_cpu
      memory         = var.ecs_memory
      environment = [
        { name = "CONTROLPLANE_CONFIG", value = local.controlplane_config_final }
      ]
      command = [
        "sh",
        "-c",
        "unset WEB_HTTP_PORT WEB_HTTP_PATH && printf '%s\n' \"$CONTROLPLANE_CONFIG\" > /tmp/controlplane-connector.properties && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/tmp/controlplane-connector.properties -jar edc-controlplane.jar"
      ]
      mount_points = []
    }
    dataplane = {
      image          = "ghcr.io/pilots-community/pilots-dataspace/dataplane:${var.image_tag}"
      container_ports = [38181, 38182, 38185]
      cpu            = var.ecs_cpu
      memory         = var.ecs_memory
      environment = [
        { name = "DATAPLANE_CONFIG", value = local.dataplane_config_final },
        { name = "PRIVATE_KEY_PEM", value = local.private_key_pem },
        { name = "PUBLIC_KEY_PEM", value = local.public_key_pem }
      ]
      command = [
        "sh",
        "-c",
        "unset WEB_HTTP_PORT WEB_HTTP_PATH && printf '%s\n' \"$DATAPLANE_CONFIG\" > /tmp/dataplane-connector.properties && printf '%s\n' \"$PRIVATE_KEY_PEM\" > /tmp/private-key.pem && printf '%s\n' \"$PUBLIC_KEY_PEM\" > /tmp/public-key.pem && exec java -Djava.security.egd=file:/dev/urandom -Dedc.fs.config=/tmp/dataplane-connector.properties -jar edc-dataplane.jar"
      ]
      mount_points = []
    }
  }

  service_load_balancers = {
    dashboard = [{ route = "dashboard", port = 80 }]
    identityhub = [
      { route = "credentials", port = 7091 },
      { route = "did-api", port = 7093 },
      { route = "identity", port = 7092 }
    ]
    controlplane = [
      { route = "dsp", port = 19194 },
      { route = "mgmt", port = 19193 }
    ]
    dataplane    = [{ route = "data", port = 38185 }]
    did-server   = [{ route = "did-server", port = 9876 }]
  }

  ghcr_images = toset(["dashboard", "identityhub", "controlplane", "dataplane"])

  service_desired_counts = {
    postgres     = 1
    vault        = 1
    did-server   = 0
    dashboard    = 0
    identityhub  = 0
    controlplane = 0
    dataplane    = 0
  }

  autoscaled_routes = {
    did-server   = "did-server"
    dashboard    = "dashboard"
    identityhub  = "credentials"
    controlplane = "dsp"
    dataplane    = "data"
  }
}
