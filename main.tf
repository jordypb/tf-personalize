provider "aws" {
  alias  = "central"
  region = "us-west-2"
}

########################
## AWS-PERSONALIZE
########################

resource "null_resource" "config_helm" {
  # depends_on = [
  #   aws_s3_bucket.personalize_bucket
  # ]
  triggers = {
    timestamp = timestamp()
  }
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    working_dir = path.cwd
    command     = <<EOS
set -euo pipefail
echo '============================='



aws s3 ls s3://${aws_s3_bucket.personalize_bucket.id}/ --region ${var.region} --profile ${var.profile} || true
aws s3 cp doc.csv s3://${aws_s3_bucket.personalize_bucket.id}/  --region ${var.region} --profile ${var.profile}
aws personalize create-dataset-group --name ${aws_s3_bucket.personalize_bucket.id}  --region ${var.region} --profile ${var.profile} || true
arn_dataset_group=$(aws personalize list-dataset-groups  --region ${var.region} --profile ${var.profile} | grep 'arn' | grep "${aws_s3_bucket.personalize_bucket.id}" | head -n1 | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')


sleep 40
aws personalize create-schema \
  --name ${aws_s3_bucket.personalize_bucket.id} \
  --schema file://schema.json --region ${var.region} --profile ${var.profile} || true
arn_schema=$(aws personalize list-schemas  --region ${var.region} --profile ${var.profile} | grep 'arn' | grep "${aws_s3_bucket.personalize_bucket.id}" | head -n1  | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')


sleep 40
aws personalize create-dataset \
  --name ${aws_s3_bucket.personalize_bucket.id} \
  --dataset-group-arn $arn_dataset_group \
  --dataset-type Interactions \
  --schema-arn $arn_schema --region ${var.region} --profile ${var.profile} || true
arn_dataset=$(aws personalize list-datasets --region ${var.region} --profile ${var.profile} | grep 'arn' | grep "${aws_s3_bucket.personalize_bucket.id}" | head -n1  | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')

sleep 120
aws personalize create-dataset-import-job \
  --job-name ${aws_s3_bucket.personalize_bucket.id} \
  --dataset-arn $arn_dataset \
  --data-source dataLocation=s3://${aws_s3_bucket.personalize_bucket.id}/doc.csv \
  --role-arn ${aws_iam_role.role_personalize.arn} --region ${var.region} --profile ${var.profile} || true
arn_dataset_import_job=$(aws personalize list-dataset-import-jobs --region ${var.region} --profile ${var.profile} | grep 'arn' | grep "${aws_s3_bucket.personalize_bucket.id}" | head -n1  | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')

sleep 240
arn_recipe=$(aws personalize list-recipes --region ${var.region} --profile ${var.profile}  | grep 'arn' | grep 'aws-user-personalization' | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')
aws personalize create-solution \
  --name ${aws_s3_bucket.personalize_bucket.id} \
  --dataset-group-arn $arn_dataset_group \
  --recipe-arn $arn_recipe --region ${var.region} --profile ${var.profile} || true
#aws personalize describe-solution --solution-arn arn:aws:personalize:us-west-2:acct-id:solution/MovieSolution  --region ${var.region} --profile ${var.profile}
arn_solution=$(aws personalize list-solutions --region ${var.region} --profile ${var.profile} | grep 'arn' | grep "${aws_s3_bucket.personalize_bucket.id}" | head -n1 | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')  

aws personalize create-solution-version \
  --solution-arn solution $arn_solution --region ${var.region} --profile ${var.profile} || true

sleep 200
arn_solution_version=$(aws personalize list-solution-versions --solution-arn $arn_solution --region ${var.region} --profile ${var.profile}| grep "${aws_s3_bucket.personalize_bucket.id}" | head -n1 | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')
aws personalize create-campaign \
  --name ${aws_s3_bucket.personalize_bucket.id} \
  --solution-version-arn $arn_solution_version \
  --min-provisioned-tps 1 --region ${var.region} --profile ${var.profile} || true

#aws personalize create-event-tracker --name saleor-prod --dataset-group-arn $arn_dataset_group --region ${var.region} --profile ${var.profile}

echo 
EOS

    environment = {
      tag = var.tag_environment
    }
  }
}

########################
## S3
########################

data "aws_iam_policy_document" "s3_policy" {
  statement {
      principals {
          type        = "Service"
          identifiers = ["personalize.amazonaws.com"]
      }
      actions = [
          "s3:GetObject",
          "s3:ListBucket"
      ]
      resources = [
          "arn:aws:s3:::${var.name}-${var.tag_environment}",
          "arn:aws:s3:::${var.name}-${var.tag_environment}/*"
      ]
  }
}

resource "aws_s3_bucket" "personalize_bucket" {
  # provider = aws.central
  bucket = "${var.name}-${var.tag_environment}"
  acl    = "private"
  policy = data.aws_iam_policy_document.s3_policy.json
  lifecycle {
    prevent_destroy = false
  }
  force_destroy = true
  provisioner "local-exec" {
    command = "echo ${self.bucket_domain_name} >> aws_s3_bucket.txt"
  }
}

resource "aws_s3_bucket_public_access_block" "bucket_access_block" {
  bucket = aws_s3_bucket.personalize_bucket.id
  block_public_acls   = true
  block_public_policy = true
}


output "bucket_name" {
  value=aws_s3_bucket.personalize_bucket.id
}

########################
## IAM
########################
resource "aws_iam_role" "role_personalize" {
  name = "role_personalize"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "personalize.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  tags = {
    tag-key = var.tag_environment
  }
}
resource "aws_iam_role_policy_attachment" "PersonalizeFull" {
    role = aws_iam_role.role_personalize.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
}
resource "aws_iam_role_policy_attachment" "S3Full" {
    role = aws_iam_role.role_personalize.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

output "iam_arn" {
  value=aws_iam_role.role_personalize.arn
}
