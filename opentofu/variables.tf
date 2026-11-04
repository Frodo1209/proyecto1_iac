# Pool de almacenamiento donde se crean los volúmenes
variable "pool" {
  type        = string
  description = "Pool de libvirt donde están las imágenes base y se crean los clones."
  default     = "default"
}

# Imágenes base (ya presentes en el pool) sobre las que se crean los clones ligeros
variable "imagen_debian" {
  type        = string
  description = "Imagen base Debian 13 para la máquina web."
  default     = "debian13-base.qcow2"
}

variable "imagen_ubuntu" {
  type        = string
  description = "Imagen base Ubuntu 26.04 para la máquina bd."
  default     = "ubuntu2604-base.qcow2"
}

# Memoria (MiB) y CPUs de cada máquina
variable "memoria_web" {
  type        = number
  description = "Memoria en MiB de la máquina web."
  default     = 1024
}

variable "memoria_bd" {
  type        = number
  description = "Memoria en MiB de la máquina bd."
  default     = 1024
}

variable "vcpu" {
  type        = number
  description = "Número de CPUs de cada máquina."
  default     = 1
}

# Clave pública SSH que se instala en las máquinas (la usa Ansible)
variable "clave_ssh" {
  type        = string
  description = "Ruta de la clave pública SSH que se instala en las máquinas."
  default     = "~/.ssh/id_ed25519.pub"
}

# Redes del escenario
variable "red_nat" {
  type        = string
  description = "Direccionamiento de la red NAT con DHCP."
  default     = "192.168.140.0/24"
}

variable "red_datos" {
  type        = string
  description = "Direccionamiento de la red de datos (IP estáticas)."
  default     = "10.0.50.0/24"
}

# IP de cada máquina en la red de datos (número de host dentro de red_datos)
variable "host_datos" {
  type        = map(number)
  description = "Número de host de cada máquina en la red de datos."
  default = {
    web = 10
    bd  = 20
  }
}
