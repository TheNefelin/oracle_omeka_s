# Oracle Cloud Free Tier - Guía para Omeka S

## Objetivo

Levantar Omeka S con MariaDB en Docker sobre una máquina virtual gratuita de Oracle Cloud (Always Free), sin generar cobros.

Arquitectura:

```
Oracle Cloud VM (Ampere A1, ARM)

Ubuntu LTS
└── Docker Compose
    ├── omeka   (erseco/alpine-omeka-s)
    └── mariadb (mariadb:lts)
Nginx/Caddy + HTTPS (opcional, en la misma VM)
```

---

# 1. Límites del Always Free (verificados agosto 2026)

| Recurso | Límite gratuito |
|---|---|
| Compute ARM (VM.Standard.A1.Flex) | **2 OCPU + 12 GB RAM** totales |
| Compute x86 (VM.Standard.E2.1.Micro) | 2 instancias (1/8 OCPU, 1 GB cada una) |
| Block Volume (boot + datos) | **200 GB** totales |
| Backups de volúmenes | 5 |
| Boot volume mínimo por instancia A1 | 47 GB |
| Object Storage | ~20 GB totales |
| Transferencia de salida (egress) | 10 TB/mes |
| Load Balancer flexible | 1 (10 Mbps) |

## ⚠️ Cambio importante de 2026

Oracle redujo el Always Free ARM: antes eran 4 OCPU / 24 GB, ahora son
**2 OCPU / 12 GB** (1,500 OCPU-horas y 9,000 GB-horas al mes).

* Las cuentas Always Free debían reducir sus instancias al nuevo límite
  **antes del 18 de agosto de 2026**; las que excedían el límite podían ser
  terminadas.
* Las cuentas Pay As You Go (con tarjeta activada) aparentemente mantienen
  4 OCPU / 24 GB sin costo dentro de esos límites.
* Verifica siempre los valores actuales en la documentación oficial:
  <https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm>

## ⚠️ Reclamo de instancias inactivas

Oracle puede **reclamar (borrar)** instancias Always Free si durante 7 días:

* CPU percentil 95 < 20 %
* Red < 20 %
* Memoria < 20 % (solo formas A1)

Mitigación: mantener actividad mínima (un sitio web con visitas o un cron
ligero suele bastar). No depender de una VM apagada la mayor parte del tiempo.

---

# 2. Reglas para evitar cobros

Antes de crear cualquier recurso, verificar:

* Que diga **"Always Free Eligible"**.
* Que la región seleccionada tenga capacidad disponible.
* Que el recurso no sea una versión de pago.

Evitar crear:

* Instancias fuera de Always Free (por ejemplo A1 con más de 2 OCPU/12 GB).
* Bases de datos gestionadas de pago.
* Load Balancers adicionales a los gratuitos.
* Volúmenes fuera de la home region (solo ahí son gratis).
* Snapshots o backups por encima de los 5 incluidos.
* IPs públicas reservadas sin usar.

---

# 3. Crear la instancia (paso a paso)

1. Console → Compute → Instances → Create Instance.
2. Shape: **Ampere → VM.Standard.A1.Flex**.
   * OCPUs: `2`
   * RAM: `12 GB`
   * Confirmar que aparece la etiqueta "Always Free Eligible".
3. Imagen: **Ubuntu 22.04 o 24.04** (canonical, ARM64).
4. Boot volume: 50 GB (dentro de los 200 GB gratuitos).
5. Clave SSH pública obligatoria; deshabilitar acceso por contraseña.
6. Red: subnet pública con IP pública efímera (gratis).

Si sale "Out of capacity" (común en regiones populares):

* Reintentar en horario de baja demanda (madrugada UTC).
* Probar otro availability domain de la región.
* Considerar actualizar a Pay As You Go: mantiene los recursos Always Free
  sin cobro y suele tener mejor disponibilidad.

---

# 4. Instalación inicial en la VM

```bash
sudo apt update && sudo apt upgrade -y
```

Instalar Docker Engine + Compose plugin (repositorio oficial):

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Cerrar sesión y volver a entrar, luego comprobar:

```bash
docker --version
docker compose version
```

---

# 5. Desplegar Omeka S

Subir al servidor el contenido de este repositorio
(`docker-compose.yml` y `.env`), por ejemplo con `scp`:

```bash
scp docker-compose.yml .env ubuntu@IP_DEL_SERVIDOR:~/omeka/
```

En el servidor:

```bash
cd ~/omeka
docker compose up -d
```

Comprobar:

```bash
docker compose ps
docker compose logs -f omeka
```

Omeka S quedará disponible en `http://IP_PUBLICA:8080`.

> Nota: la instalación automática de Omeka solo se ejecuta si
> `OMEKA_ADMIN_EMAIL`, `OMEKA_ADMIN_NAME`, `OMEKA_ADMIN_PASSWORD` y
> `OMEKA_SITE_TITLE` están definidos en `.env`, y solo la primera vez.
> Si falta cualquiera de los cuatro, el contenedor arranca igual pero la
> instalación debe completarse manualmente en `/install`.

---

# 6. Seguridad básica

## Dos capas de firewall

1. **Security List / NSG de la VCN** (consola OCI): el filtro real del
   tráfico entrante.
2. **Firewall del sistema operativo**: Ubuntu en OCI trae iptables con una
   regla restrictiva preinstalada en la cadena `INPUT`.

> **Hallazgo verificado en este despliegue:** los puertos publicados por
> contenedores Docker (`ports:` en el compose) **no pasan** por la cadena
> `INPUT` del host — Docker enruta ese tráfico por sus propias cadenas
> (`FORWARD`). Para exponer Omeka S basta abrir el puerto en el Security
> List; no hay que tocar iptables.

Las reglas manuales de iptables solo aplican a servicios corriendo
directamente en la VM (sin contenedor):

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport PUERTO -j ACCEPT
sudo netfilter-persistent save
```

La posición `INPUT 6` importa: inserta la regla antes de la que rechaza
todo el tráfico.

## Recomendaciones

* Acceso SSH solo con llaves (ya viene así por defecto).
* Instalar fail2ban.
* Cerrar el puerto 8080 al mundo si se usa proxy inverso; en ese caso cambiar
  el mapeo del compose a `127.0.0.1:8080:8080`.
* La base de datos nunca debe exponerse públicamente (el compose actual no
  publica el puerto de MariaDB: no agregar `ports` a ese servicio).

---

# 7. HTTPS con dominio propio (opcional)

El Load Balancer flexible de 10 Mbps es gratuito, pero para Omeka S lo más
simple es un proxy inverso en la misma VM:

* **Caddy**: certificados automáticos, configuración mínima.

```text
midominio.com {
    reverse_proxy localhost:8080
}
```

* Alternativa: Nginx + Certbot.

Apuntar el registro DNS `A` del dominio a la IP pública de la VM.
Considerar IP reservada (gratuita mientras esté adjunta a una instancia en uso;
una IP reservada **sin usar sí genera coste**).

---

# 8. Copias de seguridad

Nunca confiar solo en la nube.

Base de datos:

```bash
docker compose exec -T mariadb sh -c \
  'exec mariadb-dump -uomeka -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
  > backup_omeka_$(date +%F).sql
```

Archivos subidos (volumen `omeka_files`):

```bash
docker run --rm -v oracle_omeka_s_omeka_files:/data -v $(pwd):/backup \
  alpine tar czf /backup/omeka_files_$(date +%F).tar.gz -C /data .
```

> El nombre exacto del volumen puede variar (`directorio_nombre`);
> listarlo con `docker volume ls`.

Guardar copias:

* En tu equipo local (scp/rsync periódico).
* En otro proveedor si el archivo histórico es importante.
* Programar con cron en la VM, pero descargarlas fuera de la VM.

---

# 9. Control de costes

Configurar desde el primer día:

* Budget mensual (por ejemplo 1 USD) en Billing → Budgets.
* Alerta de consumo al 50 % y 100 % del budget.

Revisar periódicamente:

* Compute (que sigan dentro de 2 OCPU / 12 GB).
* Block Volume (total ≤ 200 GB).
* Backups (≤ 5).
* IPs reservadas sin adjuntar.

---

# 10. Errores comunes

## Crear una VM normal

Problema: genera coste.
Solución: confirmar "Always Free Eligible" antes de crear.

## Exceder los nuevos límites A1

Problema: con los límites de 2026, 2 OCPU / 12 GB es el máximo gratuito.
Solución: revisar el tamaño total de todas las instancias A1 de la cuenta.

## Out of capacity

Problema: no hay ARM disponible en la región para cuentas free.
Solución: reintentos en horarios valle, otros ADs, o pasar a PAYG.

## Dejar recursos abandonados

Aunque apagues una VM, estos recursos pueden seguir generando coste:

* Discos en bloque adicionales.
* IPs públicas reservadas sin adjuntar.
* Snapshots por encima del límite gratuito.
* Volumes fuera de la home region.

## Perder datos con `down -v`

`docker compose down -v` elimina los volúmenes (base de datos y archivos).
No usarlo salvo borrado deliberado. Ver README.md sección 9.

---

# 11. Plan de crecimiento

Inicio:

```
1 VM Oracle Free (ARM 2 OCPU / 12 GB)
└── Docker
    ├── Omeka S
    └── MariaDB
```

Cuando crezca:

* Separar MariaDB a otra VM A1 (si queda cupo) o a un servicio gestionado.
* Migrar a VPS dedicado u otro proveedor conservando los mismos contenedores.

---

# Checklist antes de publicar

[ ] HTTPS configurado

[ ] Backup probado (restauración verificada, no solo creación)

[ ] MariaDB sin puerto público

[ ] Security List OCI configurado (iptables no aplica a puertos de contenedores, ver §6)

[ ] Usuario SSH solo con llave

[ ] fail2ban activo

[ ] Instancia marcada como Always Free y dentro de 2 OCPU / 12 GB

[ ] Budget y alertas activados

[ ] Dominio apuntando (si aplica)

---

## Regla de oro

Si no estás seguro de si un servicio cuesta dinero:

NO lo crees hasta comprobar que dice:

**"Always Free Eligible"**
