locals {
  # Datos de cada máquina. Las MAC son fijas para que cloud-init identifique
  # cada interfaz igual en Debian y en Ubuntu (los nombres ens3/enp1s0 cambian)
  maquinas = {
    web = {
      imagen    = var.imagen_debian
      memoria   = var.memoria_web
      usuario   = "debian"
      mac_nat   = "52:54:00:14:00:10"
      mac_datos = "52:54:00:50:00:10"
    }
    bd = {
      imagen    = var.imagen_ubuntu
      memoria   = var.memoria_bd
      usuario   = "ubuntu"
      mac_nat   = "52:54:00:14:00:20"
      mac_datos = "52:54:00:50:00:20"
    }
  }

  # IP estática de cada máquina en la red de datos
  ip_datos = { for k, v in var.host_datos : k => cidrhost(var.red_datos, v) }
  mascara  = split("/", var.red_datos)[1]
}

# Clon ligero de la imagen base: solo guarda las diferencias
resource "libvirt_volume" "disco" {
  for_each         = local.maquinas
  name             = "p1-${each.key}.qcow2"
  pool             = var.pool
  base_volume_name = each.value.imagen
  base_volume_pool = var.pool
  format           = "qcow2"
}

# Disco cloud-init: usuario, clave SSH, nombre y red de cada máquina
resource "libvirt_cloudinit_disk" "cloudinit" {
  for_each = local.maquinas
  name     = "p1-${each.key}-cloudinit.iso"
  pool     = var.pool
  user_data = templatefile("${path.module}/cloud-init/user-data.tftpl", {
    hostname  = each.key
    usuario   = each.value.usuario
    clave_ssh = trimspace(file(pathexpand(var.clave_ssh)))
  })
  network_config = templatefile("${path.module}/cloud-init/network-config.tftpl", {
    mac_nat   = each.value.mac_nat
    mac_datos = each.value.mac_datos
    ip_datos  = "${local.ip_datos[each.key]}/${local.mascara}"
  })
}

resource "libvirt_domain" "maquina" {
  for_each = local.maquinas
  name     = "p1-${each.key}"
  memory   = each.value.memoria
  vcpu     = var.vcpu

  # Red NAT con DHCP (Ansible y el navegador entran por aquí)
  network_interface {
    network_id     = libvirt_network.nat.id
    mac            = each.value.mac_nat
    wait_for_lease = true
  }

  # Red de datos (IP estática configurada por cloud-init)
  network_interface {
    network_id = libvirt_network.datos.id
    mac        = each.value.mac_datos
  }

  disk { volume_id = libvirt_volume.disco[each.key].id }
  cloudinit = libvirt_cloudinit_disk.cloudinit[each.key].id

  # Consola serie: la imagen de Ubuntu la necesita para arrancar bien
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}
