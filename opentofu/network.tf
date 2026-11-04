# Red NAT con DHCP: acceso desde el anfitrión y salida a internet
resource "libvirt_network" "nat" {
  name      = "p1-nat"
  mode      = "nat"
  domain    = "p1.local"
  addresses = [var.red_nat]
  dhcp { enabled = true }
  dns { enabled = true }
  autostart = true
}

# Red de datos muy aislada (mode=none): sin DHCP ni salida, solo web <-> bd
resource "libvirt_network" "datos" {
  name      = "p1-datos"
  mode      = "none"
  autostart = true
}
