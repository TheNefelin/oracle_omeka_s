# Omeka S — Despliegue con Docker Compose

**Salvaguarda del Patrimonio Documental — Sociedad Unión y Protección de
Obreras de Valparaíso.** Archivo digital para la preservación y difusión del
acervo documental histórico de la sociedad mutualista.

Archivo histórico montado sobre [Omeka S](https://omeka.org/) usando la imagen
[`erseco/alpine-omeka-s`](https://hub.docker.com/r/erseco/alpine-omeka-s)
(multi-arquitectura, compatible ARM) y MariaDB.

Para el despliegue en Oracle Cloud Free Tier, ver
[ORACLE_CLOUD_FREE_TIER.md](ORACLE_CLOUD_FREE_TIER.md).

El avance detallado paso a paso está en [PROGRESO.md](PROGRESO.md).

---

## Plan de actividades

| Nº | Actividad | Detalle | Horas × Cant. | Total |
|---|---|---|---|---|
| 1 | Configuración de Infraestructura en OCI | Instancia Compute ARM (VM.Standard.A1.Flex, Always Free), base de datos MariaDB contenerizada con Docker Compose, Oracle Object Storage como destino de respaldos | 5 × 2 | 10 |
| 2 | Despliegue del Entorno y Core de Omeka S | Despliegue automatizado vía Docker Compose con credenciales por variables de entorno; certificados SSL de Let's Encrypt mediante proxy inverso | 5 × 3 | 15 |
| 3 | Arquitectura de Información y Configuración Semántica | Modelado de datos, vocabularios semánticos (Dublin Core, BIBO o personalizados) y plantillas de recursos (Resource Templates) para catalogación estandarizada | 5 × 6 | 30 |
| 4 | Políticas de Respaldo, Seguridad y Documentación | Tareas cron para respaldos diarios de base de datos y archivos hacia Object Storage. Documentación técnica y manual básico para administradores | 5 × 3 | 15 |

**Total: 70 horas**

> El alcance de esta tabla es la implementación tecnológica. La digitalización
> y catalogación del acervo documental corresponden al trabajo de archivo.

---

## 1. Configuración inicial (solo la primera vez)

Las credenciales viven en un archivo `.env` que **no se sube al repositorio**.
Crear uno a partir de la plantilla y editarlo:

```bash
cp .env.example .env
```

Editar `.env` y cambiar **todas** las contraseñas antes de levantar los
contenedores.

> La instalación automática de Omeka S solo corre si `OMEKA_ADMIN_EMAIL`,
> `OMEKA_ADMIN_PASSWORD` y `OMEKA_SITE_TITLE` están definidos, y solo la
> primera vez (cuando la base de datos está vacía).

---

## 2. Entrar en la carpeta del proyecto

Antes de ejecutar los comandos de Docker Compose, sitúate en la carpeta donde está `docker-compose.yml`:

```bash
cd ~/omeka
```

Puedes comprobarlo con:

```bash
pwd
```

Debería mostrar algo parecido a:

```text
/home/water/omeka
```

---

## 3. Ver el estado de los contenedores

```bash
docker compose ps
```

Muestra los contenedores de Omeka S y MariaDB y su estado.

---

## 4. Iniciar Omeka S

Si los contenedores ya existen pero están detenidos:

```bash
docker compose start
```

---

## 5. Detener Omeka S

Detiene los contenedores sin eliminarlos:

```bash
docker compose stop
```

Los datos permanecen.

---

## 6. Reiniciar Omeka S

```bash
docker compose restart
```

Útil después de realizar determinados cambios de configuración.

---

## 7. Levantar Omeka S

Para crear e iniciar los contenedores:

```bash
docker compose up -d
```

La opción `-d` significa que Docker ejecutará los contenedores en segundo plano.
Omeka arranca cuando MariaDB pasa su healthcheck (`depends_on: service_healthy`).

---

## 8. Levantar y reconstruir

Si posteriormente modificas la configuración o necesitas recrear los contenedores:

```bash
docker compose up -d --build
```

---

## 9. Detener y eliminar los contenedores

```bash
docker compose down
```

Esto elimina los contenedores, pero **conserva los volúmenes** definidos en Docker Compose.

Los datos de MariaDB y los archivos persistentes de Omeka deberían permanecer.

---

## 10. ⚠️ No eliminar los volúmenes

Evita utilizar:

```bash
docker compose down -v
```

`-v` elimina los volúmenes.

Los volúmenes pueden contener:

* Base de datos de Omeka
* Archivos subidos
* Datos persistentes

Por lo tanto, **no utilizar `down -v` salvo que quieras borrar deliberadamente los datos**.

---

## 11. Ver los logs

Para ver los logs de todos los servicios:

```bash
docker compose logs
```

Para seguir los logs en tiempo real:

```bash
docker compose logs -f
```

Para salir de la visualización:

```text
Ctrl + C
```

Esto no detiene los contenedores.

Solo Omeka:

```bash
docker compose logs -f omeka
```

Solo MariaDB:

```bash
docker compose logs -f mariadb
```

---

## 12. Comandos de inspección

Contenedores en funcionamiento (y detenidos con `-a`):

```bash
docker ps
docker ps -a
```

Imágenes descargadas:

```bash
docker images
```

Volúmenes:

```bash
docker volume ls
```

Redes:

```bash
docker network ls
```

---

# Acceder a Omeka S

El compose publica el puerto 8080:

```text
http://localhost:8080
```

También puedes utilizar:

```text
http://127.0.0.1:8080
```

Abre esa dirección en el navegador.

En producción detrás de un proxy inverso se recomienda cambiar el mapeo a
`127.0.0.1:8080:8080` para no exponer el puerto (ver ORACLE_CLOUD_FREE_TIER.md).

---

# Comprobar que el puerto está funcionando

```bash
docker compose ps
```

Deberías encontrar algo parecido a:

```text
0.0.0.0:8080->8080/tcp
```

Eso significa que el puerto 8080 del equipo está conectado con el puerto 8080 del contenedor.

---

# Reinicio después de apagar Ubuntu

El compose usa:

```yaml
restart: unless-stopped
```

Docker debería volver a iniciar los contenedores automáticamente después de reiniciar Ubuntu, siempre que Docker esté funcionando.

Puedes comprobarlo con:

```bash
docker compose ps
```

---

# Administración con omeka-s-cli

La imagen incluye [`omeka-s-cli`](https://github.com/GhentCDH/Omeka-S-Cli)
para gestionar módulos y temas desde la terminal:

```bash
docker compose exec omeka omeka-s-cli module:list
docker compose exec omeka omeka-s-cli module:download CsvImport
docker compose exec omeka omeka-s-cli theme:download foundation
```

Los módulos y temas también pueden preinstalarse añadiendo en `.env` del
compose las variables `OMEKA_MODULES` / `OMEKA_THEMES` (nombres separados por
espacios). Consulta todas las variables soportadas en la documentación de la
imagen: <https://github.com/erseco/alpine-omeka-s>

---

# Copias de seguridad

Base de datos:

```bash
docker compose exec -T mariadb sh -c \
  'exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
  > backup_omeka_$(date +%F).sql
```

Archivos subidos (volumen `omeka_files`, montado en `/var/www/html/volume`):

```bash
docker run --rm -v omeka_omeka_files:/data -v $(pwd):/backup \
  alpine tar czf /backup/omeka_files_$(date +%F).tar.gz -C /data .
```

> El nombre del volumen puede variar según el nombre de la carpeta;
> listarlo con `docker volume ls`.

Restaurar base de datos:

```bash
docker compose exec -T mariadb sh -c \
  'exec mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
  < backup_omeka_2026-01-01.sql
```

Antes de realizar operaciones destructivas, haz una copia de seguridad.

---

# Comandos rápidos

## Configurar (primera vez)

```bash
cp .env.example .env
```

## Ver estado

```bash
docker compose ps
```

## Iniciar

```bash
docker compose start
```

## Detener

```bash
docker compose stop
```

## Reiniciar

```bash
docker compose restart
```

## Crear/iniciar

```bash
docker compose up -d
```

## Ver logs

```bash
docker compose logs -f
```

## Detener y eliminar contenedores

```bash
docker compose down
```

## Entrar nuevamente en la carpeta

```bash
cd ~/omeka
```

## Abrir Omeka S

```text
http://localhost:8080
```

---

# Estructura del proyecto

```text
~/omeka/
│
├── docker-compose.yml
└── .env              # credenciales (NO versionar)
```

Los datos de los contenedores se almacenan en los volúmenes Docker definidos por Compose:

* `db_data` → datos de MariaDB
* `omeka_files` → archivos subidos a Omeka (`/var/www/html/volume`)

---

# Próximos pasos

Una vez que Omeka S esté funcionando localmente:

1. Crear el usuario administrador (automático vía `.env`).
2. Configurar el sitio.
3. Crear las primeras colecciones (item sets).
4. Definir los metadatos para libros y documentos históricos.
5. Subir material de prueba.
6. Configurar copias de seguridad automáticas.
7. Preparar el servidor para acceso desde Internet (ver ORACLE_CLOUD_FREE_TIER.md).
8. Configurar dominio y HTTPS.

---

# SSH
- Verificar clave en Windows PowerShell
```sh
Test-Path $HOME\.ssh\id_ed25519.pub
```
- Si responde True → ya tienes llave, no hagas nada más.
- Si responde False, genera una con:
```sh
ssh-keygen -t ed25519 -C "oracle-omeka"
```
- Cuando pregunte la ruta: presiona Enter (deja la default)
- Passphrase: puede quedar vacía (Enter dos veces) o ponerle una clave extra
- Luego muéstrame el contenido de la pública:
```sh
Get-Content $HOME\.ssh\id_ed25519.pub
```
- Conectarse por PowerShell
```sh
ssh ubuntu@IP_PUBLICA
```
```sh
sudo apt update && sudo apt upgrade -y
```
- **Instalación de Docker**
```sh
curl -fsSL https://get.docker.com | sudo sh
```
- Agregar tu usuario al grupo docker
- Volver a conectarse
```sh
sudo usermod -aG docker ubuntu
```
- Version de docker y compose
```sh
docker --version
docker compose version
```
- protección contra intentos de intrusión por SSH
```sh
sudo apt install fail2ban -y
```
- IMPORTANTE, respaldar claves privadas
```sh
Copy-Item $HOME\.ssh\id_ed25519 D:\Repo\Cloud\respaldo_llaves\
Copy-Item $HOME\.ssh\id_ed25519.pub D:\Repo\Cloud\respaldo_llaves\
```

