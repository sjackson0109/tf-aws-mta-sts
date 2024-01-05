domains = {
  "mytestdomain.com" = {
    route53_zone    = true
    mta_sts_enabled = true
    mta_sts_policy = {
      #Note: Only tested with STSv1
      version = "STSv1"
      mode    = "testing"
      max_age = "86400"
      #mx = "*.mytestdomain.com"
      id = "202401050201" # Consider a DATE YYYYMMDDHHMM, or comment-out for an MD5 hash instead
    }
    mta_sts_reporting = {
      enabled   = true
      forensics = false # do you want to receive forensics reporting?
      version   = "TLSRPTv1"
      endpoints = "mailto:mytest-d@tlsrpt.report-uri.com"
    }
  }
}