# Project
Deploys an end-to-end MTA-STS with TLS-RPT configuration. With a `domains` variable, as a map of customer domain-names, all hosted on AWS. Giving controls for enabling/disabling specific components, and building entirely with terraform.

# Contributions
Version:        1.0.1
Creation Date:  2023-01-02
Last Updated:   2024-01-08
Author:         Simon Jackson / sjackson0109
Contact:        simon@jacksonfamily.me


# Configurations:
Clone the `example.tfvars` file, into your own `clientname.auto.tfvars` file. Ensure the `domains` variable contains a MAP of the domains that customer needs to use, and then populate all the variable values as you see fit.
Note: If the DNS domain-name is NOT hosted on AWS Route53, each of DNS records would need to be created manually in the given provider portal.

# Terraform state (example):
The following resources exist in the state file after apply:
- data.aws_iam_policy_document.oai_access["mytestdomain.com"]
- data.aws_route53_zone.domain["mytestdomain.com"]
- aws_acm_certificate.mta_sts["mytestdomain.com"]
- aws_acm_certificate_validation.mta_sts_acme_challange["mytestdomain.com"]
- aws_cloudfront_distribution.fqdn["mytestdomain.com"]
- aws_cloudfront_origin_access_identity.mta_sts_oai["mytestdomain.com"]
- aws_route53_record.mta_sts_acme_challange["mytestdomain.com"]
- aws_route53_record.mta_sts_cloud_front_cname["mytestdomain.com"]
- aws_route53_record.mta_sts_policy["mytestdomain.com"]
- aws_route53_record.mta_sts_reporting["mytestdomain.com"]
- aws_s3_bucket.mta_sts["mytestdomain.com"]
- aws_s3_bucket_lifecycle_configuration.mta_sts["mytestdomain.com"]
- aws_s3_bucket_acl.mta_sts["mytestdomain.com"]
- aws_s3_bucket_ownership_controls.mta_sts["mytestdomain.com"]
- aws_s3_bucket_policy.oai_access["mytestdomain.com"]
- aws_s3_object.mta-sts-policy["mytestdomain.com"]
- aws_s3_object.mta_sts_folder["mytestdomain.com"]

# Protection
It might be worth signing up with `https://report-uri.com/` to gain access to a very clean user-interface to analyise website security.
Affiliated with the same site is another server-security-validation website `https://securityheaders.com` - super useful! 
and finally, i've signed up to a trail on the following website, also really useful: `https://www.hardenize.com`
https://www.hardenize.com/report

# Standards
The following RFC standards were heavily looked at in order to confirm the end to end setup:
 - [MTS-STS v1.0](https://datatracker.ietf.org/doc/html/rfc8461)
 - [TLS-RPT v1.0](https://datatracker.ietf.org/doc/html/rfc8460)