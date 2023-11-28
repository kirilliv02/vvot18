terraform {
	required_providers {
		yandex = {
			source = "yandex-cloud/yandex"
		}	
	}
	required_version = ">= 0.13"
}

locals {
  service_account_id = jsondecode(file("key.json")).service_account_id
}

provider "yandex"{
	service_account_key_file	= "key.json"
	cloud_id 			        = var.cloud_id
	folder_id			        = var.folder_id
	zone				        = "ru-central1-a"
}

resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = local.service_account_id
}

resource "yandex_storage_bucket" "bucket-photo" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "${var.user}-photo"
  acl        = "private"
  max_size = 50*1024*1024*1024
}

resource "yandex_storage_bucket" "bucket-faces" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "${var.user}-faces"
  acl        = "private"
  max_size = 50*1024*1024*1024
}

resource "yandex_ydb_database_serverless" "db" {
  name = "${var.user}-db-photo-face"
  location_id = "ru-central1"

   serverless_database {
    storage_size_limit          = 5
  }
}

resource "yandex_ydb_table" "ydb-table" {
  path = "photos"
  connection_string = yandex_ydb_database_serverless.db.ydb_full_endpoint

  column {
    name = "face_key"
    type = "String"
  }

  column {
    name = "photo_key"
    type = "String"
  }

  column {
    name = "face_name"
    type = "String"
  }

  primary_key = ["face_key"]
}

resource "yandex_message_queue" "queue-task" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  name                        = "${var.user}-task"
  visibility_timeout_seconds  = 30
  receive_wait_time_seconds   = 20
  message_retention_seconds   = 86400
}

resource "archive_file" "zip-face_detection" {
  type        = "zip"
  output_path = "face_detection.zip"

 source_dir  = "./face_detection"
}

resource "archive_file" "zip-face_cut" {
  type        = "zip"
  output_path = "face_cut.zip"

 source_dir  = "./face_cut"
}

resource "archive_file" "zip-tg_bot" {
  type        = "zip"
  output_path = "tg_bot.zip"

 source_dir  = "./tg_bot"
}

resource "yandex_function" "face-detection-function" {
  name               = "${var.user}-face-detection"
  description        = "Обнаружение лиц"
  user_hash          = "any_user_defined_string"
  runtime            = "python37"
  entrypoint         = "index.handler"
  memory             = "128"
  execution_timeout  = "10"
  service_account_id = local.service_account_id
  tags               = ["my_tag"]
  content {
    zip_filename = "face_detection.zip"
  }
  environment = {
    ACCESS_TOKEN = yandex_iam_service_account_static_access_key.sa-static-key.access_key
    SECRET_KEY = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
    QUEUE_URL = yandex_message_queue.queue-task.id
  }
 }

 resource "yandex_function" "face-cut-function" {
  name               = "${var.user}-face-cut"
  description        = "Обрезка лиц"
  user_hash          = "any_user_defined_string"
  runtime            = "python37"
  entrypoint         = "index.handler"
  memory             = "128"
  execution_timeout  = "10"
  service_account_id = local.service_account_id
  tags               = ["my_tag"]
  content {
    zip_filename = "face_cut.zip"
  }
  environment = {
    ACCESS_TOKEN = yandex_iam_service_account_static_access_key.sa-static-key.access_key
    SECRET_KEY = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
    PHOTO_BUCKET_ID = yandex_storage_bucket.bucket-photo.id
    FACES_BUCKET_ID = yandex_storage_bucket.bucket-faces.id
    DATABASE = yandex_ydb_database_serverless.db.database_path
    ENDPOINT = yandex_ydb_database_serverless.db.ydb_api_endpoint
  }
 }

 resource "yandex_function" "bot-function" {
  name               = "${var.user}-bot"
  description        = "Телеграм бот"
  user_hash          = "any_user_defined_string"
  runtime            = "python37"
  entrypoint         = "index.handler"
  memory             = "128"
  execution_timeout  = "10"
  service_account_id = local.service_account_id
  tags               = ["my_tag"]
  content {
    zip_filename = "tg_bot.zip"
  }

  environment = {
    TG_KEY = var.tg_key
    ACCESS_TOKEN = yandex_iam_service_account_static_access_key.sa-static-key.access_key
    SECRET_KEY = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
    PHOTO_BUCKET_ID = yandex_storage_bucket.bucket-photo.id
    DATABASE = yandex_ydb_database_serverless.db.database_path
    ENDPOINT = yandex_ydb_database_serverless.db.ydb_api_endpoint
    GATEWAY_URL = yandex_api_gateway.gateway.domain
  }
 }

 resource "yandex_function_iam_binding" "bot-function-iam" {
  function_id = yandex_function.bot-function.id
  role        = "functions.functionInvoker"
  members = [
    "system:allUsers",
  ]
}

 resource "yandex_function_trigger" "photo-trigger" {
  name        = "${var.user}-photo"
  description = "Триггер для бакета"
  object_storage {
    batch_cutoff = 5
     bucket_id = yandex_storage_bucket.bucket-photo.id
     create    = true
  }
  function {
    id                 = yandex_function.face-detection-function.id
    service_account_id = local.service_account_id
  }
}

resource "yandex_function_trigger" "queue_trigger" {
  name        = "${var.user}-task"
  description = "Триггер для очереди"
  message_queue {
    queue_id           = yandex_message_queue.queue-task.arn
    service_account_id = local.service_account_id
    batch_size         = "1"
    batch_cutoff       = "0"
  }
  function {
    id = yandex_function.face-cut-function.id
    service_account_id = local.service_account_id
  }
}

resource "yandex_api_gateway" "gateway"  {
  name = "${var.user}-apigw"
  description = "Gateway"
  spec = <<-EOT
openapi: 3.0.0
info:
  title: Sample API
  version: 1.0.0
paths:
  /:
    get:
      parameters:
        - name: face
          in: query
          required: true
          schema:
            type: string
      x-yc-apigateway-integration:
        type: object_storage
        bucket: ${yandex_storage_bucket.bucket-faces.id}
        object: '{face}'
        service_account_id: ${local.service_account_id}
EOT
}

data "http" "webhook" {
  url = "https://api.telegram.org/bot${var.tg_key}/setWebhook?url=https://functions.yandexcloud.net/${yandex_function.bot-function.id}"
}