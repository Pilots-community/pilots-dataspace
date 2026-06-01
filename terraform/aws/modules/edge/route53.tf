resource "aws_route53_zone" "this" {
  name = var.root_domain
}

# Authorise Amazon's CA to issue certs for this domain (incl. wildcards).
# Placed in our delegated zone so it overrides any restrictive CAA on a parent
# domain: a CA uses the CAA RRset from the closest ancestor and stops walking up
# once it finds one. Without this, ACM issuance fails with CAA_ERROR when a
# parent zone restricts issuance to other CAs.
resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.root_domain
  type    = "CAA"
  ttl     = 300

  records = [
    "0 issue \"amazon.com\"",
    "0 issuewild \"amazon.com\"",
  ]
}

resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.root_domain
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
