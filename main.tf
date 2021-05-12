########################
## AWS-PERSONALIZE
########################

resource "null_resource" "config_helm" {
  depends_on = [
    aws_s3_bucket.personalize_bucket
  ]

  triggers = {
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    working_dir = path.cwd
    command     = <<EOS
set -euo pipefail
echo '============================='
#
echo $
sleep 5
workname="sprint23"
echo $workname
aws s3 ls s3://jordypersonalize-qa/ --profile qa_profile || true
aws s3 cp doc.csv s3://jordypersonalize-qa/ --profile qa_profile
aws personalize create-dataset-group --name group-tf-person --profile qa_profile || true
arn_dataset_group=$(aws personalize  list-dataset-groups --profile qa_profile | grep 'arn' | grep 'group-tf-person' | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')


aws personalize create-schema \
  --name tf-schema \
  --schema file://schema.json --profile qa_profile || true

arn_schema=$(aws personalize list-schemas --profile qa_profile | grep 'arn' | grep 'schematest' | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')

aws personalize create-dataset \
  --name tf-person-dataset \
  --dataset-group-arn $arn_dataset_group \
  --dataset-type Interactions \
  --schema-arn $arn_schema --profile qa_profile || true
arn_dataset=$(aws personalize list-datasets --profile qa_profile | grep 'arn' | grep 'group-tf-person' | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')

aws personalize create-dataset-import-job \
  --job-name tf-person \
  --dataset-arn $arn_dataset \
  --data-source dataLocation=s3://jordypersonalize-qa/doc.csv \
  --role-arn arn:aws:iam::255366181314:role/role_personalize --profile qa_profile || true

arn_dataset_import_job=$(aws personalize list-dataset-import-jobs  --profile qa_profile |grep 'arn' | grep 'tf-person' | awk '{print $2}' | sed 's/.$//' | sed -e 's/^"//' -e 's/"$//')

echo $arn_dataset_group
echo $arn_schema
echo $arn_dataset
echo $arn_dataset_import_job

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
resource "aws_s3_bucket" "personalize_bucket" {
  bucket = "${var.name}-${var.tag_environment}"
  acl    = "public-read"
  #  policy = data.aws_iam_policy_document.website_policy.json
  lifecycle {
    prevent_destroy = false
  }
  force_destroy = true
  provisioner "local-exec" {
    command = "echo ${self.bucket_domain_name} >> aws_s3_bucket.txt"
  }
}


########################
## IAM
########################
# https://stackoverflow.com/questions/44565879/terraform-error-creating-iam-role-malformedpolicydocument-has-prohibited-fiel
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
resource "aws_iam_role_policy_attachment" "ec2-read-only-policy-attachment" {
    role = aws_iam_role.role_personalize.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
}

output "iam_arn" {
  value=aws_iam_role.role_personalize.arn
}
