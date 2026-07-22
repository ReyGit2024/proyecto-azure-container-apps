resource "azurerm_container_app" "app" {
  name                = var.container_app_name
  resource_group_name = var.rg_name
    revision_mode                = "Single"
  container_app_environment_id = var.environment_id

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = var.container_app_name
      image  = var.image_name
      cpu    = 0.5
      memory = "1Gi"
    }
  }



  registry {
    server   = var.acr_login_server
    identity = "system"
  }
}

# Asignar rol AcrPull al Container App para leer del ACR
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.app.identity[0].principal_id
}