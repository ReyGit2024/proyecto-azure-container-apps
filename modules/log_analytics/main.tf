resource "azurerm_log_analytics_workspace" "law" {
  name                = "loganalytics2026"
  location            = var.location
  resource_group_name = var.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
