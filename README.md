# Omeka S — Despliegue con Docker Compose en Oracle Cloud Free Tier

**Salvaguarda del Patrimonio Documental — Sociedad Unión y Protección de
Obreras de Valparaíso.** Archivo digital para la preservación y difusión del
acervo documental histórico de la sociedad mutualista.

Montado sobre [Omeka S](https://omeka.org/) usando la imagen
[`erseco/alpine-omeka-s`](https://hub.docker.com/r/erseco/alpine-omeka-s)
(multi-arquitectura, compatible ARM) y MariaDB.

| Documento | Contenido |
|---|---|
| [PROGRESO.md](PROGRESO.md) | Bitácora del despliegue: avance, fases y decisiones |
| [ORACLE_CLOUD_FREE_TIER.md](ORACLE_CLOUD_FREE_TIER.md) | Manual técnico de Oracle Cloud Always Free |
| [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/) | Sitio oficial del programa y sus límites vigentes |

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│ CAPA ORACLE CLOUD (Always Free)                         │
│                                                         │
│  Región: Chile West · AD-1                              │
│  ┌───────────────────────────────────────────┐          │
│  │ VM omeka-vm                               │          │
│  │ VM.Standard.A1.Flex (ARM Ampere)          │          │
│  │ 2 OCPU · 12 GB RAM                        │          │
│  │ Ubuntu 24.04 LTS aarch64                  │          │
│  │ Boot volume ~47 GB (cupo total: 200 GB)   │          │
│  │                                           │          │
│  │  Docker Engine + Compose                  │          │
│  │  ├─ fail2ban / iptables                   │          │
│  │  └─ Red interna Docker                    │          │
│  │     ├─ omeka    (erseco/alpine-omeka-s)   │◄── :8080 │──► Internet
│  │     └─ mariadb  (mariadb:lts)             │   sin puerto público
│  │                                           │          │
│  │  Volúmenes persistentes:                  │          │
│  │  ├─ db_data      → base de datos          │          │
│  │  └─ omeka_files  → documentos subidos     │          │
│  └───────────────────────────────────────────┘          │
│  VCN + subnet pública + IP efímera                      │
│                                                         │
│  Object Storage (~20 GB) → destino de respaldos         │
└─────────────────────────────────────────────────────────┘
```

Cómo se conectan las piezas:

* El navegador del público entra por el puerto **8080** al contenedor `omeka`
  (que incluye servidor web + PHP).
* `omeka` habla con `mariadb` **solo por la red interna de Docker** — la base
  de datos nunca se expone a Internet.
* Todo dato que importa vive en volúmenes (`db_data`, `omeka_files`): los
  contenedores pueden borrarse y recrearse sin perder nada.
* Las credenciales viajan desde `.env` hacia los contenedores como variables
  de entorno (`.env` no se versiona).
* Los respaldos diarios salen hacia Object Storage (Fase 7).

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

## Inicio rápido

```bash
cp .env.example .env    # editar contraseñas ANTES de continuar
docker compose up -d    # crea e inicia ambos contenedores
docker compose ps       # verificar estado healthy/running
```

Omeka S queda disponible en `http://localhost:8080`. La instalación automática
corre solo la primera vez, usando los datos de `.env`.

> ⚠️ **Nunca ejecutar `docker compose down -v`**: borra los volúmenes con toda
> la base de datos y los archivos subidos.

---

## Comandos esenciales

| Acción | Comando |
|---|---|
| Estado de contenedores | `docker compose ps` |
| Iniciar (contenedores existentes) | `docker compose start` |
| Detener (conserva datos) | `docker compose stop` |
| Reiniciar | `docker compose restart` |
| Crear/iniciar en segundo plano | `docker compose up -d` |
| Ver logs en vivo (todos) | `docker compose logs -f` |
| Logs solo de Omeka / solo BD | `docker compose logs -f omeka` / `-f mariadb` |
| Eliminar contenedores (**conserva** volúmenes) | `docker compose down` |

Inspección general: `docker ps`, `docker images`, `docker volume ls`,
`docker network ls`.

---

## Administración con omeka-s-cli

La imagen incluye [`omeka-s-cli`](https://github.com/GhentCDH/Omeka-S-Cli):

```bash
docker compose exec omeka omeka-s-cli module:list
docker compose exec omeka omeka-s-cli module:download CsvImport
docker compose exec omeka omeka-s-cli theme:download foundation
```

Módulos y temas también pueden preinstalarse con las variables
`OMEKA_MODULES` / `OMEKA_THEMES` (ver
[documentación de la imagen](https://github.com/erseco/alpine-omeka-s)).

---

## Copias de seguridad

Base de datos:

```bash
docker compose exec -T mariadb sh -c \
  'exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
  > backup_omeka_$(date +%F).sql
```

Archivos subidos (volumen `omeka_files`; confirmar nombre con `docker volume ls`):

```bash
docker run --rm -v omeka_omeka_files:/data -v $(pwd):/backup \
  alpine tar czf /backup/omeka_files_$(date +%F).tar.gz -C /data .
```

Restaurar base de datos:

```bash
docker compose exec -T mariadb sh -c \
  'exec mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
  < backup_omeka_FECHA.sql
```

Antes de cualquier operación destructiva: backup primero, siempre.

---

## Estructura del proyecto

```text
~/omeka/
├── docker-compose.yml   # infraestructura versionada (sin secretos)
└── .env                 # credenciales (NO versionar)
```

Volúmenes Docker persistentes:

* `db_data` → datos de MariaDB
* `omeka_files` → archivos subidos a Omeka (`/var/www/html/volume`)

Los contenedores usan `restart: unless-stopped`: tras reiniciar la máquina,
Docker los levanta automáticamente.

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
