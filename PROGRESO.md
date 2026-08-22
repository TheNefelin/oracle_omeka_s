# Progreso — Omeka S en Oracle Cloud

**Proyecto:** Salvaguarda del Patrimonio Documental — Sociedad Unión y
Protección de Obreras de Valparaíso. Archivo digital del acervo documental
histórico de la sociedad mutualista, publicado con Omeka S sobre infraestructura
gratuita (Oracle Cloud Free Tier).

Bitácora del despliegue paso a paso. Este archivo se va actualizando en cada
sesión: los pasos hechos llevan `[x]`, los pendientes `[ ]`.

**Dónde estamos ahora:** Fase 2 completada ✔ → Fase 3 (desplegar Omeka S).

---

## Arquitectura del proyecto

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
│  Object Storage (~20 GB) → destino de respaldos [F7]    │
└─────────────────────────────────────────────────────────┘

Credenciales: .env (fuera de git) — Config: docker-compose.yml (versionado)
```

**Principios decididos:**

| Decisión | Motivo |
|---|---|
| Contenedores desechables, volúmenes sagrados | Reinicios/actualizaciones sin pérdida de datos |
| MariaDB sin puerto público | Solo accesible desde la red interna Docker |
| `down -v` prohibido | Elimina los volúmenes con todos los datos |
| Omeka S (no Classic) | Multi-sitio, metadatos enlazados, plataforma activa |
| MariaDB en contenedor (no BD gestionada) | Omeka S no soporta Autonomous DB; menos superficie de cobro |
| Despliegue manual ahora, CI/CD después (Fase 8) | Entender antes de automatizar |

---

## Referencia rápida de documentos

| Archivo | Para qué sirve |
|---|---|
| `PROGRESO.md` | **Este archivo**: plan y avance del proyecto |
| `ORACLE_CLOUD_FREE_TIER.md` | Manual técnico de Oracle Cloud (límites, seguridad, HTTPS) |
| `README.md` | Manual operativo de Docker Compose (comandos diarios) |
| `.env.example` | Plantilla de credenciales |

### Datos del servidor

> 🔒 Los valores reales (IP pública, nombres de red) **no se versionan**.
> Guárdalos localmente, por ejemplo en un archivo `servidor.local.md`
> excluido por `.gitignore`, o en tu gestor de contraseñas.

| Dato | Valor |
|---|---|
| Nombre instancia | `omeka-vm` |
| IP pública | *(ver archivo local — efímera)* |
| Usuario SSH | `ubuntu` |
| Región | Chile West (Valparaíso), AD-1 |
| Shape | VM.Standard.A1.Flex — 2 OCPU / 12 GB |
| SO | Canonical Ubuntu 24.04 |
| VCN / Subnet | creadas por asistente (10.0.0.0/24) |

---

## Fase 0 — Cuenta Oracle Cloud ✅

- [x] Cuenta creada
- [x] Home region: **Chile West (Valparaíso)** — fija, no se puede cambiar.
      Todos los recursos Always Free se crean AQUÍ
- [x] Cobro ~1000 CLP verificado: preautorización bancaria (~USD 1),
      se revierte sola. No aparece en Cost Analysis porque no es consumo
- [x] Cost Analysis revisado (1–21 ago): vacío, nada consumiendo ✔
- [x] Advertencia de "región adicional" descartada: innecesaria para este
      proyecto, una sola región es lo correcto
- [x] Budget mensual con alertas ✔ ("Alerta-Gastos", Active, alertas 50%/100%)
- [ ] Confirmar en el banco (en ~5 días) que los 1000 CLP se revirtieron

---

## Fase 1 — Crear la máquina virtual

Guía detallada: `ORACLE_CLOUD_FREE_TIER.md` sección 3.

- [x] Generar par de llaves SSH en el PC local (`$HOME\.ssh\id_ed25519`)
- [x] Compute → Instances → Create Instance → **omeka-vm** creada (2026-08-21)
- [x] Shape: VM.Standard.A1.Flex — 2 OCPU / 12 GB ("Always Free Eligible")
- [x] Imagen: Ubuntu 24.04 (aarch64/ARM64)
- [x] Boot volume: default (~47 GB)
- [x] Llave SSH pública pegada en OCI
- [x] IP pública asignada post-creación (efímera) — valor en archivo local
- [x] Conectarse por SSH la primera vez ✔ (2026-08-21)

> Nota: el asistente de creación bloqueó la asignación de IP pública en el
> formulario (bug de consola); se asignó después desde VNIC → IPv4 Addresses
> → Edit → Ephemeral public IP. Quedó funcionando igual.

---

## Fase 2 — Preparar el servidor ✅

- [x] `sudo apt update && sudo apt upgrade -y` (+ reboot)
- [x] Instalar Docker: `curl -fsSL https://get.docker.com | sudo sh` (v29.7.2)
- [x] `sudo usermod -aG docker ubuntu` + relogin ✔
- [x] Verificado: Docker 29.7.2 / Compose v5.5.0 sin sudo
- [x] Fail2ban instalado ✔
- [ ] Respaldo de la llave privada SSH en ubicación segura (pendrive/gestor) ← importante

---

## Fase 3 — Desplegar Omeka S

- [x] Local: `cp .env.example .env` y editar contraseñas reales
- [x] En VM: `mkdir -p ~/omeka`
- [x] Subir archivos: `scp docker-compose.yml .env ubuntu@IP_PUBLICA:~/omeka/` ✔ (2026-08-21)
- [x] En el servidor: `cd ~/omeka && docker compose up -d` ✔ (imágenes ARM descargadas, red y volúmenes `db_data`/`omeka_files` creados)
- [x] Verificar: `docker compose ps` (ambos healthy) ✔ (2026-08-21)

---

## Fase 4 — Abrir acceso web

- [x] Consola OCI: VCN → Security Lists → Default Security List → regla de
      entrada para **8080/tcp**, descripción "Omeka S temporal" ✔
      (2026-08-21). Las reglas de 80/443 se agregan en Fase 6 con HTTPS
- [x] iptables del SO: **no requerido para puertos de contenedores** —
      Docker enruta ese tráfico por sus cadenas `FORWARD` sin pasar por la
      cadena `INPUT` del host. Solo filtra el Security List de OCI
      (hallazgo documentado en ORACLE_CLOUD_FREE_TIER.md §6)
- [x] Abrir `http://IP_PUBLICA:8080` desde el navegador ✔ sitio accesible
- [x] Instalación completada manualmente vía `/install` y acceso a `/admin`
      verificado ✔ (2026-08-21)

---

## Fase 5 — Configurar el contenido (dentro de Omeka S)

- [ ] Cambiar idioma a español si corresponde
- [ ] Crear item sets (colecciones) para libros y documentos históricos
- [ ] Definir plantillas de metadatos
- [ ] Crear el sitio público y su tema
- [ ] Subir material de prueba

---

## Fase 6 — Dominio y HTTPS (opcional pero recomendado)

- [ ] Registrar/comprar dominio (fuera de Oracle; hay gratuitos como DuckDNS)
- [ ] Apuntar registro DNS A → IP pública de la VM
- [ ] Proxy inverso con Caddy (HTTPS automático) — guía en
      `ORACLE_CLOUD_FREE_TIER.md` sección 7
- [ ] Cambiar mapeo del puerto a `127.0.0.1:8080:8080` en el compose

---

## Fase 7 — Copias de seguridad

- [ ] Backup manual de prueba (comandos en `README.md`)
- [ ] Restauración de prueba (un backup que nunca se restauró no sirve)
- [ ] Cron semanal en la VM + descargar copia al PC local

---

## Fase 8 — CI/CD (futuro, tras tener HTTPS funcionando)

> Decisión: se mantiene en la arquitectura por valor real (evita config
> drift entre repo y servidor, simplifica actualizaciones). Fuera del
> alcance de las 70 horas del informe; se documenta como trabajo futuro.

- [ ] Workflow de GitHub Actions: SSH a la VM + `docker compose up -d` en cada push
- [ ] Secrets en GitHub: clave SSH privada e IP (nunca en el código)

---

## Plan de actividades (informe de horas)

| Nº | Actividad | Fases relacionadas |
|---|---|---|
| 1 | Infraestructura OCI: Compute ARM + MariaDB contenerizada + Object Storage (respaldos) | Fase 0–1, 2, 7 |
| 2 | Despliegue entorno + core Omeka S + SSL Let's Encrypt | Fase 3, 4, 6 |
| 3 | Arquitectura de información y configuración semántica (vocabularios, plantillas) | Fase 5 |
| 4 | Políticas de respaldo/seguridad + documentación | Fase 7 + docs del repo |

Total estimado: 70 horas (detalle completo en el informe institucional).

> Nota: el borrador original mencionaba "Oracle Base Database / MySQL
> HeatWave"; se corrigió a MariaDB contenerizada porque Base Database es de
> pago y HeatWave añade complejidad sin beneficio para Omeka S.

---

## Rutina mensual (después de todo lo anterior)

- [ ] Cost Analysis = $0.00
- [ ] Instancias dentro de 2 OCPU / 12 GB
- [ ] Block volumes ≤ 200 GB totales
- [ ] Sin IPs reservadas sin usar
- [ ] El sitio sigue respondiendo (evita reclamación por instancia idle)

---

## Registro de incidencias y decisiones

| Fecha | Evento |
|---|---|
| 2026-08-21 | Cuenta creada. Cobro ~1000 CLP identificado como preautorización bancaria |
| 2026-08-21 | Región home fijada: Chile West (Valparaíso). Se decide NO suscribir regiones adicionales |
| 2026-08-21 | Budget "Alerta-Gastos" creado y Active ($1/mes, alertas 50% y 100%). Cuenta blindada ✔ |
| 2026-08-21 | Decisión de arquitectura: datos en volúmenes Docker (`db_data`, `omeka_files`) sobre el boot volume; contenedores desechables. Prohibido `down -v`. Backups como capa extra (Fase 7) |
| 2026-08-21 | Llaves SSH generadas (ed25519). Clave pública lista para pegar en OCI |
| 2026-08-21 | Decisión: despliegue con Docker (no nativo). Razones: misma config local/producción, upgrades simples, migración fácil, aislamiento |
| 2026-08-21 | Despliegue exitoso: `omeka` + `omeka-mariadb` healthy en ARM. Sitio accesible por IP:8080 |
| 2026-08-21 | Hallazgo: puertos Docker no requieren iptables del host (solo Security List OCI); se corrige documentación §6 de la guía Oracle |
| 2026-08-21 | Falso positivo "`.env` no copiado": los archivos con punto inicial son ocultos para `ls`; verificar siempre con `ls -la` |
