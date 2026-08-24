# SSH — Acceso y preparación del servidor

Guía paso a paso para conectarse a la VM de Oracle Cloud desde Windows
PowerShell e instalar el software base del servidor.

> **Estado:** estos pasos ya fueron ejecutados (ver Fases 0–2 en
> [PROGRESO.md](PROGRESO.md)). Este documento queda como registro del
> procedimiento. Único pendiente: respaldo de llaves (paso 9).

---

## 1. Verificar la llave SSH en Windows

```powershell
Test-Path $HOME\.ssh\id_ed25519.pub
```

* Si responde `True` → ya tienes llave, no hagas nada más.
* Si responde `False`, genera una:

```powershell
ssh-keygen -t ed25519 -C "oracle-omeka"
```

* Ruta: presiona Enter (deja la predeterminada).
* Passphrase: puede quedar vacía (Enter dos veces) o ponerle una clave extra.

## 2. Mostrar la clave pública

```powershell
Get-Content $HOME\.ssh\id_ed25519.pub
```

Ese contenido es el que se pega en la consola de Oracle Cloud al crear la
instancia (o luego en *Instance details → Edit → Add SSH keys*).

## 3. Conectarse por SSH

```powershell
ssh ubuntu@IP_PUBLICA
```

Reemplazar `IP_PUBLICA` por la IP de la instancia. La primera vez pregunta
si confías en el host: responder `yes`.

## 4. Actualizar el sistema

```bash
sudo apt update && sudo apt upgrade -y
```

Si el kernel se actualizó, reiniciar y volver a conectarse: `sudo reboot`.

## 5. Instalar Docker Engine + Compose

```bash
curl -fsSL https://get.docker.com | sudo sh
```

## 6. Agregar el usuario al grupo docker

```bash
sudo usermod -aG docker ubuntu
exit
```

Cerrar sesión y volver a conectarse para que el grupo aplique.

## 7. Verificar versiones

```bash
docker --version
docker compose version
```

## 8. Protección contra intrusiones (fail2ban)

Bloquea automáticamente IPs con intentos repetidos de intrusión por SSH:

```bash
sudo apt install fail2ban -y
sudo systemctl status fail2ban --no-pager
```

## 9. Respaldo de llaves privadas ⚠️ PENDIENTE

La llave privada es **la única forma** de entrar al servidor. Si se pierde,
el acceso se pierde. Respaldarla en carpeta segura (fuera del repositorio):

```powershell
Copy-Item $HOME\.ssh\id_ed25519 D:\Repo\Cloud\respaldo_llaves\
Copy-Item $HOME\.ssh\id_ed25519.pub D:\Repo\Cloud\respaldo_llaves\
```

Alternativa recomendada adicional: gestor de contraseñas (Bitwarden, KeePass).

## 10. Instalar Omeka
- Crear carpeta en la VM:
```sh
ssh ubuntu@IP_PUBLICA
mkdir -p ~/omeka
```
- Subir los archivos desde tu PC:
```sh
cd D:\Repo\Cloud\oracle_omeka_s
scp docker-compose.yml .env ubuntu@IP_PUBLICA:~/omeka/
ssh ubuntu@IP_PUBLICA
cd ~/omeka 
ls -la
docker compose ps
docker compose up -d
docker compose ps
docker compose logs -f omeka
```

## 11. Omeka Themes
- [omeka themes](https://omeka.org/s/themes/)
```sh
cd omeka
docker compose exec omeka omeka-s-cli theme:list
docker compose exec omeka omeka-s-cli theme:download lively
```

## 12. Script respaldo MariaDB + Archivos
```sh
cd D:\Repo\Cloud\oracle_omeka_s
ssh ubuntu@IP_PUBLICA "mkdir -p ~/omeka/scripts"
scp scripts/respaldo.sh ubuntu@IP_PUBLICA:~/omeka/scripts/
```
- Ejecutar el script
```sh
chmod +x ~/omeka/scripts/respaldo.sh
~/omeka/scripts/respaldo.sh
ls -lh ~/omeka-backups/
```
- Ver recursos físicos
```sh
docker run --rm -v omeka_omeka_files:/data alpine find /data/files -type f
```
- Restaurar respaldo

> Los nombres de archivo (`FECHA_HHMM_db.sql`, `FECHA_HHMM_files.tar.gz`)
> cambian con cada respaldo — usa el más reciente de `~/omeka-backups/`.

```sh
cd ~/omeka
# 1. Detener Omeka para que nada escriba durante la operación
docker compose stop omeka
# 2. Vaciar y recrear la base de datos (usa el nombre de TU .env)
docker compose exec -T mariadb sh -c 'exec mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE $MARIADB_DATABASE; CREATE DATABASE $MARIADB_DATABASE;"'
# 3. Importar el respaldo de las 22:32
docker compose exec -T mariadb sh -c 'exec mariadb -u root -p"$MARIADB_ROOT_PASSWORD" $MARIADB_DATABASE' < ~/omeka-backups/20260824_1815_db.sql
# 4. Reincorporar los archivos del respaldo al volumen
docker run --rm -v omeka_omeka_files:/data -v ~/omeka-backups:/backup alpine tar xzf /backup/20260824_1815_files.tar.gz -C /data
# 5. Corregir propietario de los archivos (igual que hace el contenedor)
docker run --rm -v omeka_omeka_files:/data alpine chown -R nobody:nobody /data
# 6. Levantar Omeka
docker compose start omeka
```

- Verificar la recuperación:
```sh
docker run --rm -v omeka_omeka_files:/data alpine find /data/files -type f
```
El PDF eliminado debe reaparecer, y el elemento volver a la lista de
Elementos del panel con su ficha funcional.

- Backup
```sh
ssh ubuntu@IP_PUBLICA
sudo apt install -y rclone
rclone version    # verificar que instaló
```
- Configuración 
```sh
mkdir -p ~/.config/rclone
nano ~/.config/rclone/rclone.conf
```
```sh
[oci-backups]
type = s3
provider = Other
access_key_id = ACCESS_KEY
secret_access_key = SECRET_ACCESS_KEY
endpoint = https://axxyz5xiuzy3.compat.objectstorage.sa-valparaiso-1.oraclecloud.com
```
- Actualizar respaldo.sh
```sh
scp scripts/respaldo.sh ubuntu@IP_PUBLICA:~/omeka/scripts/
```
- Ejecutar script
```sh
bash ~/omeka/scripts/respaldo.sh
```
- Cronometro para ejecutar el .sh
```sh
crontab -e
```
- Todos los domingos a las 3:00 de la madrugada, ejecuta el script de respaldo
```sh
0 3 * * 0 /home/ubuntu/omeka/scripts/respaldo.sh
```
- Verificar la tarea
```sh
crontab -l
```
- Cambiar zona horaria de la VM y reiniciar crono
```sh
sudo timedatectl set-timezone America/Santiago
sudo systemctl restart cron
```

---

## Referencias

* Manual completo de Oracle Cloud: [ORACLE_CLOUD_FREE_TIER.md](ORACLE_CLOUD_FREE_TIER.md)
* Estado del despliegue: [PROGRESO.md](PROGRESO.md)
