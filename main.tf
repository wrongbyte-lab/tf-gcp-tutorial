variable "google_project_name" {}

provider "google" {
	project = "${var.google_project_name}"
	region = "us-central1"
}

data "archive_file" "my_function_zip" {
    type = "zip"
    source_dir = "${path.module}/src"
    output_path = "${path.module}/src.zip"
}

resource "google_cloudfunctions_function" "my_function" {
    name = "myFunction"
    description = "the function we are going to deploy"
    runtime = "nodejs16"
    trigger_http     = true
    ingress_settings = "ALLOW_ALL"
    source_archive_bucket = google_storage_bucket.function_source_bucket.name
    source_archive_object = google_storage_bucket_object.function_source_bucket_object.name
}

resource "google_storage_bucket" "function_source_bucket" {
  name = "function-bucket-1234"
  location = "us-central1"
}

resource "google_storage_bucket_object" "function_source_bucket_object" {
  name   = "function-bucket-object"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.my_function_zip.output_path
}

output "function_url_trigger" {
    value = google_cloudfunctions_function.my_function.https_trigger_url
}

resource "google_cloudfunctions_function_iam_member" "my_second_fn_iam" {
  cloud_function = google_cloudfunctions_function.my_function.name
  member         = "allUsers"
  role           = "roles/cloudfunctions.invoker"
}