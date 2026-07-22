locals {
  bucket_name             = "${data.google_project.project_gc.name}-${terraform.workspace}-multicloud"
  rg_name                 = "rg-acr-aca"
  vnet_name               = "vnet-empresa"
  location                = "northeurope"
  name_app                = "name-app"
  name_alaw               = "name_alaw"
  name_Environment        = "entorno-container-app"
  name_container_app      = "contapp2026"
  name_container_registry = "registrycont2026"

  # Variables centralizadas
  subscription_id = "4e8541c6-fa25-42a6-b9e1-7e1baf87aa54"
  acr_name        = "registrycont2026"
  image_name      = "imagen-plan"
  image_path      = "./api"
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket      = "bucket_backend"
    prefix      = "terraform"
    credentials = "../el-plan-iac.json"
  }
}

provider "azurerm" {
  features {}
}

provider "google" {
  project     = "el-plan-iac"
  credentials = file("../el-plan-iac.json")
}

data "google_project" "project_gc" {}

resource "google_storage_bucket" "static-site" {
  depends_on    = [data.google_project.project_gc]
  name          = local.bucket_name
  location      = "EU"
  force_destroy = true

  versioning {
    enabled = true
  }
}

#####################################################
## RESOURCE GROUP
#####################################################

module "rg" {
  source   = "./modules/rg"
  rg_name  = local.rg_name
  location = local.location
}

#####################################################
## LOG ANALYTICS
#####################################################

module "log_analytics" {
  source         = "./modules/log_analytics"
  rg_name        = module.rg.rg_name
  location       = module.rg.location
  workspace_name = local.name_alaw
  depends_on     = [module.rg]
}

#####################################################
## ACR
#####################################################

module "acr" {
  source        = "./modules/acr"
  rg_name       = module.rg.rg_name
  location      = module.rg.location
  acr_name      = local.name_container_registry
  admin_enabled = true
  depends_on    = [module.rg]
}

#####################################################
## PUSH IMAGEN DOCKER AL ACR
#####################################################

resource "null_resource" "push_docker_image" {
  depends_on = [module.acr]

  provisioner "local-exec" {
    command = <<EOT
      az login
      az account set --subscription ${local.subscription_id}
      az acr login --name ${local.acr_name}
      docker build -t ${local.image_name} "${local.image_path}"
      docker tag ${local.image_name} ${local.acr_name}.azurecr.io/${local.image_name}:latest
      docker push ${local.acr_name}.azurecr.io/${local.image_name}:latest
    EOT
  }
}

#####################################################
## CONTAINER ENV
#####################################################

module "container_env" {
  source           = "./modules/container_env"
  rg_name          = module.rg.rg_name
  location         = module.rg.location
  env_name         = local.name_Environment
  log_analytics_id = module.log_analytics.workspace_id
  depends_on       = [module.log_analytics]
}

#####################################################
## CONTAINER APP
#####################################################

module "container_app" {
  source             = "./modules/container_app"
  rg_name            = module.rg.rg_name
  container_app_name = local.name_container_app
  environment_id     = module.container_env.environment_id
  acr_login_server   = module.acr.login_server
  image_name         = "${module.acr.login_server}/imagen-plan:latest"
  acr_id             = module.acr.acr_id

  depends_on = [
    module.container_env,
    module.acr,
    null_resource.push_docker_image
  ]
}

#####################################################
## DAR PERMISOS AcrPULL
#####################################################

resource "azurerm_role_assignment" "acr_pull" {
  scope = module.acr.acr_id
  role_definition_name = "AcrPull"
  principal_id = module.container_app.principal_id

  depends_on           = [module.container_app]
}
