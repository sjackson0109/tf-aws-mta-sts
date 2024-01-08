# Project
Deploys an end-to-end MTA-STS with TLS-RPT configuration, for a nested tier of customer domain-names all hosted on AWS, with terraform.

# Note to self
If the DNS domain-name is NOT hosted on AWS Route53, each DNS records in the PLAN would need to be created manually.


# Terraform state (example):
data.aws_iam_policy_document.oai_access["mytestdomain.com"]
data.aws_route53_zone.domain["mytestdomain.com"]
aws_acm_certificate.mta_sts["mytestdomain.com"]
aws_acm_certificate_validation.mta_sts_acme_challange["mytestdomain.com"]
aws_cloudfront_distribution.fqdn["mytestdomain.com"]
aws_cloudfront_origin_access_identity.mta_sts_oai["mytestdomain.com"]
aws_route53_record.mta_sts_acme_challange["mytestdomain.com"]
aws_route53_record.mta_sts_cloud_front_cname["mytestdomain.com"]
aws_route53_record.mta_sts_policy["mytestdomain.com"]
aws_route53_record.mta_sts_reporting["mytestdomain.com"]
aws_s3_bucket.mta_sts["mytestdomain.com"]
aws_s3_bucket_acl.mta_sts["mytestdomain.com"]
aws_s3_bucket_ownership_controls.mta_sts["mytestdomain.com"]
aws_s3_bucket_policy.oai_access["mytestdomain.com"]
aws_s3_object.mta-sts-policy["mytestdomain.com"]
aws_s3_object.mta_sts_folder["mytestdomain.com"]

# RFC Standards
 - [ MTS-STS v1.0 ](https://tools.ietf.org/html/rfc8461)
 - [ TLS-RPT v1.0 ](https://tools.ietf.org/html/rfc8460)