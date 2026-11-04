# IP de cada máquina: la de la red NAT (DHCP) y la de la red de datos (estática)
output "maquinas" {
  value = {
    for k, d in libvirt_domain.maquina : k => {
      ip_nat   = try(d.network_interface[0].addresses[0], "No disponible")
      ip_datos = local.ip_datos[k]
    }
  }
}
