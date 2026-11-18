# Proyecto 1 - Infraestructura como código

Despliegue de una aplicacion web con base de datos [guestbook_php](https://github.com/josedom24/guestbook_php) sobre KVM/libvirt, y de una segunda aplicación de prueba (un tablón de notas) en contenedores **LXC** con **Caddy** y **PostgreSQL**:

- **OpenTofu** nos ayudara a crear el escenario.
- **Ansible** configurara las máquinas y desplegara la aplicación.

El escenario se podra destruir y levantar en cualquier momento con **dos simples comandos**

---

## Esquema del escenario

```
                 Anfitrión (192.168.140.1)
                          │
        ┌─────────────────┴───────────────────┐  p1-nat  192.168.140.0/24
        │        NAT + DHCP (salida a internet) │
   eth0 │ DHCP                           DHCP │ eth0
 ┌──────┴──────┐                       ┌──────┴──────┐
 │     web     │                       │     bd      │
 │  Debian 13  │                       │ Ubuntu 26.04│
 │ Apache+PHP  │                       │   MariaDB   │
 └──────┬──────┘                       └──────┬──────┘
   eth1 │ 10.0.50.10                10.0.50.20 │ eth1
        └─────────────────┬───────────────────┘
                          │  p1-datos  10.0.50.0/24
                     red muy aislada (sin DHCP ni salida)
```

La máquina `lxc` está en las mismas redes (`192.168.140.x` y `10.0.50.30`) y dentro tiene sus propios contenedores:

```
                   p1-nat (192.168.140.x)
                          │ eth0 :80
 ┌────────────────────────┴──────────────────────────┐
 │ lxc (Debian 13)        │ DNAT :80 -> 10.0.3.10:80 │
 │                        │                          │
 │      lxcbr0 10.0.3.1 ──┴──────────┐  NAT + DHCP   │
 │        │                          │  (lxc-net)    │
 │ ┌──────┴───────┐          ┌───────┴──────┐        │
 │ │    caddy     │  :5432   │   postgres   │        │
 │ │  10.0.3.10   │ ───────> │  10.0.3.20   │        │
 │ │Caddy+PHP-FPM │          │ PostgreSQL 17│        │
 │ └──────────────┘          └──────────────┘        │
 └───────────────────────────────────────────────────┘
```

| Máquina | Sistema      | Red `p1-nat` (DHCP) | Red `p1-datos` (estática) | Función                 |
|---------|--------------|---------------------|---------------------------|-------------------------|
| `web`   | Debian 13    | 192.168.140.x       | 10.0.50.10                | Apache + PHP, aplicación |
| `bd`    | Ubuntu 26.04 | 192.168.140.x       | 10.0.50.20                | MariaDB                 |
| `lxc`   | Debian 13    | 192.168.140.x       | 10.0.50.30                | Contenedores LXC caddy y postgres |

* Las tres máquinas son **clones ligeros** (backing store) de las imágenes base del pool `default`.
* MariaDB **solo escucha en 10.0.50.20** y el usuario `guestbook` **solo puede conectarse desde 10.0.50.10**.
* Cada interfaz tiene una MAC fija y cloud-init la reconoce por la MAC, así la configuración de red es igual en Debian (`ens3`) y en Ubuntu (`enp1s0`): siempre queda `eth0` (NAT) y `eth1` (datos).

## Requisitos

* OpenTofu, libvirt/KVM y Ansible (con las colecciones `community.mysql` y `community.general`: `ansible-galaxy collection install -r ansible/requirements.yaml`).
* En el pool `default` de libvirt, las imágenes base `debian13-base.qcow2` y `ubuntu2604-base.qcow2` (redimensionadas). Se pueden cambiar con las variables `imagen_debian` e `imagen_ubuntu`.
* Una clave SSH en `~/.ssh/id_ed25519.pub` (variable `clave_ssh`): OpenTofu la mete en las máquinas con cloud-init y Ansible la usa para entrar.

## Despliegue

```bash
cd opentofu
tofu init        # solo la primera vez
tofu apply
cd ../ansible
ansible-playbook site.yaml
```

`tofu apply` crea las redes, los discos, las máquinas y además **genera el inventario `ansible/hosts`** a partir de las IP que ha dado el DHCP (`opentofu/inventario.tf` + `inventario.tftpl`), con los grupos `servidores_web`, `servidores_bd` y `servidores_lxc`. El playbook espera a que las máquinas terminen de arrancar antes de configurarlas.

Para acceder a la aplicación, añade al `/etc/hosts` del anfitrión la IP NAT de `web` (sale en `tofu output`):

```
192.168.140.x   www.fran.org
```

y abre <http://www.fran.org>.

El tablón de notas de la máquina `lxc` se abre directamente con su IP NAT: `http://192.168.140.x` (Caddy responde a cualquier nombre en el puerto 80).

Para destruir el escenario: `tofu destroy` (en `opentofu/`).

## Máquina lxc: Caddy y PostgreSQL en contenedores

Se usa **LXC clásico** (`lxc-create`, `lxc-start`, `lxc-attach`), sin LXD ni Incus:

* **Red**: `lxc-net` crea el puente `lxcbr0` (`10.0.3.0/24`) con NAT y un dnsmasq que da DHCP y DNS. Cada contenedor tiene una **MAC fija** en su configuración y dnsmasq le asigna siempre la misma IP (`/etc/lxc/dnsmasq.conf`): `caddy` 10.0.3.10 y `postgres` 10.0.3.20.
* **Contenedores**: se crean con la plantilla `download` (Debian 13 de images.linuxcontainers.org), arrancan con la máquina (`lxc.start.auto = 1`) y son privilegiados (los crea root).
* **postgres**: PostgreSQL 17 escucha en la red de los contenedores y `pg_hba.conf` solo deja entrar al usuario `notas` desde 10.0.3.10 (el contenedor caddy). No es accesible desde fuera de la máquina `lxc`.
* **caddy**: Caddy sirve la aplicación con `php_fastcgi` hacia PHP-FPM (`php-pgsql`). `config.php` está fuera del DocumentRoot, en `/etc/notas/`.
* **Acceso desde fuera**: el servicio `lxc-dnat` carga una tabla de nftables propia (`/etc/lxc/lxc-dnat.nft`) que redirige el puerto 80 de `eth0` al contenedor caddy. No se activa `nftables.service`, porque su `flush ruleset` borraría las reglas de `lxc-net`.
* **Cómo configura Ansible los contenedores**: se conecta solo a la máquina `lxc`. Los ficheros de configuración se escriben directamente en el rootfs de cada contenedor (`/var/lib/lxc/<nombre>/rootfs/...`) y los comandos se ejecutan dentro con `lxc-attach` (variable `lxc_exec`). Así los contenedores no necesitan SSH.
* **La aplicación** es un tablón de notas (`ansible/roles/lxc_caddy/files/index.php`): muestra el contenedor y la versión de PostgreSQL a la que se conecta, y permite publicar y borrar notas.

Comprobaciones:

```bash
ssh debian@<ip_lxc> sudo lxc-ls -f                 # caddy y postgres RUNNING con su IP
curl -s http://<ip_lxc> | grep conectado           # la aplicación llega a PostgreSQL

# PostgreSQL rechaza al usuario notas si no viene del contenedor caddy
ssh debian@<ip_lxc> "sudo lxc-attach -n postgres -- psql -h 10.0.3.20 -U notas notas"
#   -> no pg_hba.conf entry for host "10.0.3.20"
```

## Estructura

```
opentofu/
├── provider.tf            # provider libvirt 0.8.3 y local
├── variables.tf           # imágenes, memoria, CPUs, clave SSH, redes e IP
├── network.tf             # p1-nat (NAT+DHCP) y p1-datos (muy aislada)
├── main.tf                # discos (clones ligeros), cloud-init y máquinas
├── output.tf              # IP de las máquinas
├── inventario.tf          # genera ../ansible/hosts
├── inventario.tftpl
└── cloud-init/            # plantillas user-data y network-config
ansible/
├── ansible.cfg
├── site.yaml
├── requirements.yaml
├── group_vars/            # all, servidores_web, servidores_bd, servidores_lxc
└── roles/
    ├── commons/           # actualiza el sistema y paquetes comunes
    ├── bd/                # MariaDB, base de datos, usuario y tablas
    ├── web/               # Apache + PHP, virtual host y aplicación
    ├── lxc/               # LXC, red lxcbr0, contenedores y DNAT
    ├── lxc_postgres/      # PostgreSQL en el contenedor postgres
    └── lxc_caddy/         # Caddy + PHP-FPM y tablón de notas en el contenedor caddy
```

## Variables

* **OpenTofu** (`opentofu/variables.tf`): `imagen_debian`, `imagen_ubuntu`, `memoria_web`, `memoria_bd`, `memoria_lxc`, `vcpu`, `clave_ssh`, `red_nat`, `red_datos`, `host_datos`. Se pueden cambiar con `-var` o un `terraform.tfvars`.
* **Ansible** (`ansible/group_vars/`): nombre de la base de datos, usuario y contraseña, nombre del virtual host (`www.fran.org`), DocumentRoot y versión de la aplicación. En `servidores_lxc.yaml`: red de los contenedores, imagen, IP y MAC de cada contenedor, puertos redirigidos y datos de la base de datos del tablón. Las IP de la red de datos se toman del inventario que genera OpenTofu.

## Idempotencia

* La aplicación se descarga fichero a fichero de un commit fijo del repositorio (`app_version`), así que `get_url` no vuelve a cambiar nada.
* `config.php` se genera con una plantilla.
* `schema.sql` solo se importa si la tabla `messages` no existe (se consulta antes con `SHOW TABLES`).
* En la máquina `lxc`, los contenedores solo se crean si no existe su rootfs, los paquetes solo se instalan si `dpkg -s` dice que faltan, y el usuario, la base de datos y la tabla de PostgreSQL se consultan antes de crearlos.
* La segunda ejecución de `ansible-playbook site.yaml` termina con `changed=0`.

## Comprobaciones

```bash
# Desde web: la conexión funciona
ssh debian@<ip_web> "mariadb -h 10.0.50.20 -u guestbook -p guestbook -e 'SHOW TABLES;'"

# Desde bd (otra IP): se rechaza (Host 'bd-datos' is not allowed to connect)
ssh ubuntu@<ip_bd> "mariadb -h 10.0.50.20 -u guestbook -p guestbook -e 'SHOW TABLES;'"
```
