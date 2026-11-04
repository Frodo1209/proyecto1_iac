# Genera el inventario de Ansible a partir de las IP del escenario
resource "local_file" "inventario" {
  filename        = "${path.module}/../ansible/hosts"
  file_permission = "0644"
  content = templatefile("${path.module}/inventario.tftpl", {
    maquinas = {
      for k, d in libvirt_domain.maquina : k => {
        ip_nat   = try(d.network_interface[0].addresses[0], "")
        ip_datos = local.ip_datos[k]
        usuario  = local.maquinas[k].usuario
      }
    }
  })
}
