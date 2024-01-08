locals {
  # Couple of queries to shrink the data-set in tfvars > time-saver

  domains_hosted_on_route53                      = try({ for k, v in var.domains : k => v if try(v.route53_zone, false) == true }, {})
  domains_hosted_elsewhere                       = try({ for k, v in var.domains : k => v if try(v.route53_zone, false) == false }, {}) #considering outputting these to an ascii table during terraform apply
  domains_hosted_on_route53_with_mta_sts_enabled = try({ for k, v in var.domains : k => v if try(v.route53_zone, false) == true && try(v.mta_sts_enabled, false) == true }, {})

}

################################################################
##    AWS LOGGED-IN-USER DATA                                 ##
################################################################
data "aws_caller_identity" "current" {}

################################################################
##    ROUTE 53 RESOURCES                                      ##
################################################################
# retrieve all zones that exist in route53 (map of domains could have externally hosted zones)
data "aws_route53_zone" "domain" {
  for_each = local.domains_hosted_on_route53
  name     = each.key
  provider = aws.useast1
}

# create the record for ACME challange required by the ACMs certificate issuer
resource "aws_route53_record" "mta_sts_acme_challange" {
  for_each   = local.domains_hosted_on_route53_with_mta_sts_enabled
  name       = tolist(aws_acm_certificate.mta_sts[each.key].domain_validation_options)[0].resource_record_name
  type       = tolist(aws_acm_certificate.mta_sts[each.key].domain_validation_options)[0].resource_record_type
  zone_id    = data.aws_route53_zone.domain[each.key].id
  records    = [tolist(aws_acm_certificate.mta_sts[each.key].domain_validation_options)[0].resource_record_value]
  ttl        = 60
  depends_on = [aws_acm_certificate.mta_sts]
}

resource "aws_route53_record" "mta_sts_cloud_front_cname" {
  for_each = local.domains_hosted_on_route53_with_mta_sts_enabled
  name     = "mta-sts.${each.key}"
  type     = "CNAME"
  zone_id  = data.aws_route53_zone.domain[each.key].id

  # EITHER:
  ttl      = "300"
  records = [
    "${aws_cloudfront_distribution.fqdn[each.key].domain_name}."
  ]
  # OR
  # alias { 
  #   evaluate_target_health = false
  #   name                   = aws_cloudfront_distribution.fqdn[each.key].domain_name
  #   zone_id                = aws_cloudfront_distribution.fqdn[each.key].hosted_zone_id
  # }
  # NOTE: The ALIAS mechanism works in creating the DNS record; but AWS REFUSES to answer the dns query. Cannot work out why, no time.
  depends_on = [data.aws_route53_zone.domain, aws_cloudfront_distribution.fqdn]
}

resource "aws_route53_record" "mta_sts_reporting" {
  for_each = local.domains_hosted_on_route53_with_mta_sts_enabled
  zone_id  = data.aws_route53_zone.domain[each.key].id
  name     = "_smtp._tls.${each.key}"
  type     = "TXT"
  ttl      = "300"
  records = [
    each.value.mta_sts_reporting.enabled == true ? (
      "v=${try(each.value.mta_sts_reporting.version, "TLSRPTv1")}; ${(each.value.mta_sts_reporting.forensics == true ? "ruf" : "rua")}=${try(each.value.mta_sts_reporting.endpoints, "none")};"
    ) : ( 
      "v=${try(each.value.mta_sts_reporting.version, "TLSRPTv1")};"
    )
  ]
  depends_on = [data.aws_route53_zone.domain, aws_cloudfront_distribution.fqdn]
}

resource "aws_route53_record" "mta_sts_policy" {
  for_each = local.domains_hosted_on_route53_with_mta_sts_enabled
  zone_id  = data.aws_route53_zone.domain[each.key].id
  name     = "_mta-sts.${each.key}"
  type     = "TXT"
  ttl      = "300" # TODO update to 3600, after testing
  records = [
    "v=STSv1; id=${
      try(each.value.mta_sts_policy.id,
        md5(
          jsonencode(
            { "version" = "${each.value.mta_sts_policy.version}", "mode" = "${each.value.mta_sts_policy.mode}", "max_age" = try(each.value.mta_sts_policy.max_age, "86400"),
              "mx"      = try(formatlist("mx: %s\n", each.value.mta_sts_policy.mx), "*.${each.key}")
            }
          )
        )
      )
    }",
  ]
  depends_on = [data.aws_route53_zone.domain, aws_s3_bucket.mta_sts]
}

################################################################
##    TIME RESOURCES - only wait 1x interval!                 ##
################################################################
# We need to wait until the DNS record propagates, usually just 60 seconds
resource "time_sleep" "wait_on_dns_ttl" {
  create_duration = "60s"
  depends_on      = [aws_route53_record.mta_sts_acme_challange]
}
# We also need to wait 15-20 minutes for Cloud Front to instigate the container-states, usually 15 minutes
resource "time_sleep" "cloud_front_container_provision" {
  create_duration = "5m"
  depends_on      = [aws_cloudfront_distribution.fqdn]
}

################################################################
##    ACM RESOURCES                                           ##
################################################################
# create a ACM certificate for all domains that exist in route53, that have mta_sts enabled in config
resource "aws_acm_certificate" "mta_sts" {
  for_each          = local.domains_hosted_on_route53_with_mta_sts_enabled
  domain_name       = "mta-sts.${each.key}"
  validation_method = "DNS"
  provider = aws.useast1
}

# AS A CERT REQUEST IS UNDERWAY, BEFORE VALIDATION, THE ISSUER CREATES AN ACMEv1 CHALLANGE. THIS IS ADDED AS A DNS RECORD (CNAME)
# SEE aws_route53_record.mta_sts_acme_challange

# Complete the ACME Validation
resource "aws_acm_certificate_validation" "mta_sts_acme_challange" {
  for_each                = local.domains_hosted_on_route53_with_mta_sts_enabled
  certificate_arn         = aws_acm_certificate.mta_sts[each.key].arn
  validation_record_fqdns = [aws_route53_record.mta_sts_acme_challange[each.key].fqdn]
  provider = aws.useast1
  depends_on              = [aws_route53_record.mta_sts_acme_challange, time_sleep.wait_on_dns_ttl]
}


################################################################
##    S3 RESOURCES                                            ##
################################################################
# Create an S3 bucket to hold /.well-known/mta-sts.txt inside
resource "aws_s3_bucket" "mta_sts" {
  for_each = local.domains_hosted_on_route53_with_mta_sts_enabled
  bucket   = "mta-sts.${each.key}"
}

# Move the bucket to Glacier storage, much cheaper!
resource "aws_s3_bucket_lifecycle_configuration" "mta_sts" {
  for_each = try(aws_s3_bucket.mta_sts,{})
  bucket = each.value.id
  rule {
    id      = ".well-known"
    status  = "Enabled"
    # Current version transition - move all files to glacier/nas storage after 30-days, reducing costs in month 2 onwards by approx 50%
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
  depends_on = [aws_s3_bucket.mta_sts]
}

# Set the s3 bucket objects to inherit ownership from the bucket
resource "aws_s3_bucket_ownership_controls" "mta_sts" {
  for_each = local.domains_hosted_on_route53_with_mta_sts_enabled
  bucket   = aws_s3_bucket.mta_sts[each.key].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
  depends_on = [aws_s3_bucket.mta_sts]
}

# Set bucket ACL policy to `private`
resource "aws_s3_bucket_acl" "mta_sts" {
  for_each   = local.domains_hosted_on_route53_with_mta_sts_enabled
  bucket     = aws_s3_bucket.mta_sts[each.key].id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.mta_sts]
}

# Create the `.well-known` folder
resource "aws_s3_object" "mta_sts_folder" {
  for_each     = local.domains_hosted_on_route53_with_mta_sts_enabled
  bucket       = aws_s3_bucket.mta_sts[each.key].id
  content_type = "application/x-directory"
  key          = ".well-known/"
  acl          = "private"
  depends_on   = [aws_s3_bucket.mta_sts]
}

# Create the `.well-known/mta-sts.txt` policy file
resource "aws_s3_object" "mta_sts_policy" {
  for_each     = local.domains_hosted_on_route53_with_mta_sts_enabled
  bucket       = aws_s3_bucket.mta_sts[each.key].id
  key          = ".well-known/mta-sts.txt"
  content_type = "text/plain"
  # content = jsonencode(
  #   { "version" = "${each.value.mta_sts_policy.version}", "mode" = "${each.value.mta_sts_policy.mode}", "max_age" = try(each.value.mta_sts_policy.max_age, "86400"),
  #     "mx"      = try(formatlist("mx: %s\n", each.value.mta_sts_policy.mx), "*.${each.key}")
  #   }
  # )
  content = "version: ${each.value.mta_sts_policy.version} \nmode: ${each.value.mta_sts_policy.mode} \nmax_age: ${each.value.mta_sts_policy.max_age} \nmx: *.${each.key}"
  etag = md5( "version: ${each.value.mta_sts_policy.version} \nmode: ${each.value.mta_sts_policy.mode} \nmax_age: ${each.value.mta_sts_policy.max_age} \nmx: *.${each.key}" )
  depends_on = [aws_s3_object.mta_sts_folder]
}

# Attach the IAM policies to each bucket
resource "aws_s3_bucket_policy" "oai_access" {
  for_each   = local.domains_hosted_on_route53_with_mta_sts_enabled
  bucket     = aws_s3_bucket.mta_sts[each.key].id
  policy     = data.aws_iam_policy_document.oai_access[each.key].json
  depends_on = [aws_s3_bucket.mta_sts, data.aws_iam_policy_document.oai_access]
}

################################################################
##    CLOUD-FRONT RESOURCES                                   ##
################################################################
# Create the Legacy OAI service/access identity
resource "aws_cloudfront_origin_access_identity" "mta_sts_oai" {
  for_each = local.domains_hosted_on_route53_with_mta_sts_enabled
  comment  = "Legacy OAI user for Cloud-Front to proxy http access to the backend S3 bucket"
}

# Create the Cloud-Front Distribution Point, Origin, certificate-bindings and Behaviour

# Future improvement: consider 1x CF Dist point, with a dynamic origin and viwer_certificate for each domain. The 'forwarded_values' in cache behaviour might present another complexity. No time to develop this now, multiple instances will have to do.
resource "aws_cloudfront_distribution" "fqdn" {
  for_each = local.domains_hosted_on_route53_with_mta_sts_enabled
  enabled  = true
  aliases  = ["mta-sts.${each.key}"]
  origin {
    domain_name = aws_s3_bucket.mta_sts[each.key].bucket_regional_domain_name
    origin_id   = "mta-sts.${each.key}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.mta_sts_oai[each.key].cloudfront_access_identity_path
    }
  }
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.mta_sts[each.key].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    compress = true
    target_origin_id = "mta-sts.${each.key}"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "https-only" #HTTP is unsupported, as the S3 bucket has this as a private-bucket
    min_ttl                = (each.value.mta_sts_policy.mode == "testing" ? 10 : null)
    default_ttl            = (each.value.mta_sts_policy.mode == "testing" ? 300 : null)
    max_ttl                = (each.value.mta_sts_policy.mode == "testing" ? 300 : null)
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

################################################################
##    IAM DATA                                                ##
################################################################
# Create a JSON document for IAM Policies
data "aws_iam_policy_document" "oai_access" {
  for_each = local.domains_hosted_on_route53_with_mta_sts_enabled
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.mta_sts[each.key].arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [ aws_cloudfront_origin_access_identity.mta_sts_oai[each.key].iam_arn ]
    }
  }
  depends_on = [aws_s3_bucket.mta_sts, aws_cloudfront_origin_access_identity.mta_sts_oai]
}


