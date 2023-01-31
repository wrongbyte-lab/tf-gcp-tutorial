Previously, [we've deployed a cloud function in Google Cloud](https://github.com/wrongbyte-lab/cf). We have done it through the GCP's command line utility.
Now, we can create and run the same Cloud Function using Terraform.

### Why to use Terraform?
When we deployed our function using Google's SDK directly, we had to use a command with several flags that could be grouped together in a `deploy.sh` script:
```bash
gcloud functions deploy $FN_NAME \
    --entry-point=$FN_ENTRY_POINT \
    --runtime=nodejs16 \
    --region=us-central1 \
    --trigger-http \
    --allow-unauthenticated
```
In this script, we are specifying *exactly* how we want our cloud function to be. The flags specify the entrypoint, the runtime, region, trigger and etc.

One could say we are *describing* how our infrastructure should be. Exactly what we could do with infrastructure as code - in this case, using Terraform!

## Creating a `main.tf`
The `main.tf` file is the starting point for Terraform to build and manage your infrastructure.

We can start by adding a *provider*.  A provider is a plugin that lets you use the API operations of a specific cloud provider or service, such as AWS, Google Cloud, Azure etc.
```hcl
provider "google" {
	project = "project_name"
	region = "us-central1"
}
```

But let's think about the following scenario: what if you wanted to create a *generic template* infrastructure that could be reused for different projects other than `project_name`?
Here it comes the `tfvars` file: a file in which you can put all your environment variables:
```env
google_project = "project_name"
```

And now you can use this variable in your `main.tf`:
```hcl
provider "google" {
	project = "${var.project_name}"
	region = "us-central1"
}
```

Now, let's start to add the infrastructure specific to our project!

## Terraform `resource`s
A Terraform resource is a **unit of Terraform configuration that represents a real-world infrastructure object**, such as an EC2 instance, an S3 bucket, or a virtual network. In our case, we are going to represent a cloud function.
We define these resources in blocks, where we **describe the desired state of the resource** - including properties such as the type, name, and other configuration options.

> Understanding how state works is important because, every time Terraform applies changes to the infrastructure of our projects, **it updates resources to match the desired state defined in the Terraform configuration.**

### What's inside a `resource`?
Besides the definition previously mentioned, a Terraform resource is - syntatically - a block compound of three parts:
-   The type of the resource, such as `aws_instance` or `google_compute_instance`.
-   The name of the resource, **which must be unique within the Terraform configuration.**
-   Configuration options for the resource (the *state*, as said before), such as the image ID for an EC2 instance or the bucket name for an S3 bucket.

Alright. We are getting there.
Let's then create the `resource` block for our Google Cloud Function!

> Each resource block has its specific properties. You can find them in the docs of the Terraform provider you are using. For example, here is the docs for the cloud function we'll be creating:
> https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloudfunctions_function

We can start by defining a few things, such as the `name`, `description` and `runtime`:
```hcl
resource "google_cloudfunctions_function" "myFunction" {
	name = "myFunction"
	description = "the function we are going to deploy"
	runtime = "nodejs16"
}
```

>Note: you may have noticed that we are repeating `myFunction` twice here.
>It happens because we have to set a *name for the resource* - in this case, `myFunction`, which is translated to `google_cloudfunctions_function.my_second_fn` in Terraform - and we also have to set the value of the *name field* of the block, which is going to be used by Google - not Terraform - to identify your function.

## The source code
However, even though we know these basic properties of our function, *where is the source code?* In the previous tutorial, Google SDK was able to look into our root directory to find our `index.js` file. But here, we only have a Terraform file which specifies our desired state, but no mentions at all about where to find the source code for our function. Let's fix it.

### Creating a bucket
From the docs, we know we have several ways available to specify in our resource block where to find the source code of our function. Let's do it with a storage bucket.
```hcl
resource "google_storage_bucket" "source_bucket" {
	name = "function-bucket"
	location = "us-central1"
}
```

Now we have a bucket, but we also need a bucket *object* that stores our source code.
```hcl
resource "google_storage_bucket_object" "source_code" {
	name = "object-name"
	bucket = google_storage_bucket.bucket.name
	source = "path/to/local/file"
}
```

Note the *source* field.
Accordingly to the docs, we need to use a `.zip` file to store the source code (as well as other files such as `package.json`). We can *transform* our directory into a `zip` file using a `data "archive_file"` block:
```hcl
data "archive_file" "my_function_zip" {
	type = "zip"
	source_dir = "${path.module}/src"
	output_path = "${path.module}/src.zip"
}
```

> `path.module` is the filesystem path of the module where the expression is placed.

Therefore, now our `main.tf` looks like this:
```hcl
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
}

resource "google_storage_bucket" "source_bucket" {
  name = "function-bucket"
  location = "us-central1"
}

resource "google_storage_bucket_object" "source_code" {
  name   = "object-name"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.my_function_zip.output_path
}
```

We can deploy! But... There's still some things missing.

Using Google SDK we were able to get the URL of our function - since it has a HTTP trigger. It would be good to get this URL righ away.
Also, we needed to set IAM policies to let everyone trigger our function. How to do something similar in Terraform?

We can fix these things by adding two blocks: one which is for IAM policies and another to display the output - an output block.

> In Terraform, an output block is used to define the desired values that should be displayed when Terraform applies changes to infrastructure.
> If we run `terraform plan` right now, we can see some properties that will be known once the infrastructure is created. And `https_trigger_url` is exactly what we are looking for!
> ![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/mjk05r60um32uzd097j5.png)



```hcl
output "function_url_trigger" {
    value = google_cloudfunctions_function.my_function.https_trigger_url
}

resource "google_cloudfunctions_function_iam_member" "my_second_fn_iam" {
  cloud_function = google_cloudfunctions_function.my_function.name
  member         = "allUsers"
  role           = "roles/cloudfunctions.invoker"
}
```

Now, we can run `terraform apply` and get, as the output, the URL that triggers our function:


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/jhye8kee09l8mntkg495.png)


And finally, we can trigger it:
![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/0deseeh6av9y6qww9syl.png)



