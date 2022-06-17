resource "azurerm_network_security_group" "inbound" {
  name                = "${var.name}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group_name}"

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "${var.ssh_port}"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = "${var.tags}"
}

resource "azurerm_public_ip" "linux" {
  name                         = "${var.name}"
  location                     = "${var.location}"
  resource_group_name          = "${var.resource_group_name}"
  allocation_method            = "Dynamic"
  idle_timeout_in_minutes      = 30
  domain_name_label            = "${var.resource_group_name}-${var.name}"

  tags = "${var.tags}"
}

resource "azurerm_network_interface" "nic" {
  name                      = "${var.name}"
  location                  = "${var.location}"
  resource_group_name       = "${var.resource_group_name}"
  //network_security_group_id = "${azurerm_network_security_group.inbound.id}"

  ip_configuration {
    name                          = "${var.name}-config"
    subnet_id                     = "${var.subnet_id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.linux.id}"
  }

  tags = "${var.tags}"
}

# Create (and display) an SSH key
resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "mytfvm" {
  name                  = "${var.name}"
  location              = "${var.location}"
  resource_group_name   = "${var.resource_group_name}"
  availability_set_id   = "${var.availability_set_id}"
  network_interface_ids = ["${azurerm_network_interface.nic.id}"]
  size                  = "${var.vm_size}"

  
  computer_name  = "${var.name}"
  admin_username = "${var.admin_username}"
  disable_password_authentication = true
  custom_data    = "${var.cloud_config}"
  admin_ssh_key {
    // key_data = "${var.ssh_key}"
    // path     = "/home/${var.admin_username}/.ssh/authorized_keys"
    username   = "azureuser"
    public_key = tls_private_key.example_ssh.public_key_openssh
  }

  os_disk {
    name              = "${var.name}-os"
    caching           = "ReadWrite"
    storage_account_type = "${var.storage_type}"
  }

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-11"
    sku       = "11-gen2"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = "${var.diag_storage_primary_blob_endpoint}"
  }

  tags = "${var.tags}"
}

// This is used for Microsoft.OSTCExtensions 2.3 (the portal default)
data "template_file" "wadcfg" {
  template = "${file("${path.module}/diagnostics/wadcfg.xml.tpl")}"

  vars = {
    virtual_machine_id = "${azurerm_linux_virtual_machine.mytfvm.id}"
  }
}

// This is used for Microsoft.OSTCExtensions 2.3 (the portal default)
data "template_file" "settings" {
  template = "${file("${path.module}/diagnostics/settings2.3.json.tpl")}"

  vars = {
    xml_cfg           = "${base64encode(data.template_file.wadcfg.rendered)}"
    diag_storage_name = "${var.diag_storage_name}"
  }
}

/*
// This is used only if you require the Azure.Linux.Diagnostics 3.0 extension
data "azurerm_storage_account_sas" "diagnostics" {
  connection_string = "${var.diag_storage_primary_connection_string}"
  https_only        = true

  resource_types {
    service   = false
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = true
    file  = false
  }

  start  = "2018-06-01"
  expiry = "2118-06-01"

  permissions {
    read    = true
    write   = true
    delete  = false
    list    = true
    add     = true
    create  = true
    update  = true
    process = false
  }
}

data "template_file" "settings" {
  template = "${file("${path.module}/diagnostics/settings3.0.json.tpl")}"

  vars = {
    diag_storage_name = "${var.diag_storage_name}"
    virtual_machine_id = "${azurerm_linux_virtual_machine.mytfvm.id}"
  }
}
*/

data "template_file" "protected_settings" {
  template = "${file("${path.module}/diagnostics/protected_settings2.3.json.tpl")}"

  vars = {
    diag_storage_name               = "${var.diag_storage_name}"
    diag_storage_primary_access_key = "${var.diag_storage_primary_access_key}"

    # if using Azure.Linux.Diagnostics 3.0, you MUST supply a SAS and skip the leading "?".
    # diag_storage_sas = "${substr(data.azurerm_storage_account_sas.diagnostics.sas,1,-1)}"
  }
}

/*
resource "azurerm_virtual_machine_extension" "diagnostics" {
  name                       = "diagnostics"
  resource_group_name        = "${var.resource_group_name}"
  location                   = "${var.location}"
  virtual_machine_name       = "${azurerm_linux_virtual_machine.mytfvm.name}"
  publisher                  = "Microsoft.OSTCExtensions"
  type                       = "LinuxDiagnostic"
  type_handler_version       = "2.3"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_linux_virtual_machine.mytfvm]

  settings           = "${data.template_file.settings.rendered}"
  protected_settings = "${data.template_file.protected_settings.rendered}"
  tags               = "${var.tags}"
}
*/

output "virtual_machine" {
  value = "${azurerm_linux_virtual_machine.mytfvm.id}"
}
