terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
 
  required_version = ">= 1.3.0"
}
 
provider "aws" {
  region = var.aws_region
}
 
resource "random_id" "bucket_suffix" {
  byte_length = 4
}
 
resource "aws_s3_bucket" "static_site_bucket" {
  bucket = "static-site-${random_id.bucket_suffix.hex}"
 
  tags = {
    Name = "StaticSiteBucket"
  }
}
 
resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.static_site_bucket.id
 
  index_document {
    suffix = "index.html"
  }
}
 
resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.static_site_bucket.id
 
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
 
resource "aws_s3_object" "website_files" {
  for_each = fileset("${path.module}/website", "**")
 
  bucket = aws_s3_bucket.static_site_bucket.id
  key    = each.value
  source = "${path.module}/website/${each.value}"
  etag   = filemd5("${path.module}/website/${each.value}")
 
  content_type = lookup({
    html = "text/html"
    css  = "text/css"
    js   = "application/javascript"
    png  = "image/png"
    jpg  = "image/jpeg"
    jpeg = "image/jpeg"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")
}
 
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "s3-oac-${aws_s3_bucket.static_site_bucket.bucket}"
  description                       = "Access control for S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
 
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"
 
  origin {
    domain_name = aws_s3_bucket.static_site_bucket.bucket_regional_domain_name
    origin_id   = "s3-origin"
 
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }
 
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-origin"
 
    viewer_protocol_policy = "redirect-to-https"
 
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
 
  viewer_certificate {
    cloudfront_default_certificate = true
  }
 
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
 
resource "aws_s3_bucket_policy" "cf_access" {
  bucket = aws_s3_bucket.static_site_bucket.id
 
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "AllowCloudFrontReadAccess",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.static_site_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}
 
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}
output "bucket_name" {
  value = aws_s3_bucket.static_site_bucket.bucket
 
}
