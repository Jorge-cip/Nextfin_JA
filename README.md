# Nextfin_JA: Tu Nube Personal y Centro Multimedia

Nextfin_JA es una suite de auto-alojamiento (self-hosted) preconfigurada que integra **Nextcloud**, **Jellyfin** y **OnlyOffice**, todo orquestado con Docker y diseñado para una implementación rápida en servidores Linux.

Esta solución te permite tener tu propia nube personal para archivos, un completo centro multimedia para tus películas y series, y una potente suite de ofimática para editar documentos en línea, todo en un solo lugar y bajo tu control.

## 📚 Stack de Servicios

- **Nextcloud:** Plataforma de almacenamiento en la nube, calendario, contactos y mucho más.
- **Jellyfin:** Servidor de streaming multimedia para organizar y disfrutar tus películas, series y música.
- **OnlyOffice:** Suite de ofimática compatible con documentos de Microsoft Office.
- **Apache:** Servidor web de alto rendimiento para servir Nextcloud.
- **PostgreSQL:** Base de datos robusta para Nextcloud y OnlyOffice.
- **Redis:** Caché en memoria para acelerar el rendimiento de Nextcloud.
- **Restic:** Herramienta para copias de seguridad incrementales, seguras y eficientes.

## ✨ Características Principales

- **Instalación Automatizada:** Un único script (`setup.sh`) se encarga de configurar todo el entorno.
- **Optimización de Rendimiento:** Configuraciones preajustadas para PHP, Apache y Redis para un rendimiento óptimo.
- **Gestión de Multimedia:** Incluye scripts para optimizar y estandarizar tu biblioteca de imágenes y videos.
- **Backups Integrados:** Scripts listos para usar que facilitan la creación y restauración de copias de seguridad.
- **Seguridad Mejorada:** El script configura permisos de archivos y directorios siguiendo buenas prácticas.

---

## 🚀 Instalación (Paso a Paso)

Sigue estos pasos para desplegar la suite. Los comandos están listos para copiar y pegar en tu terminal.

### 1. Requisitos Previos

Solo necesitas tener `git` y `dos2unix` instalados en tu servidor. El script de instalación se encargará del resto de dependencias.

```bash
sudo apt-get update
sudo apt-get install -y git dos2unix
```

### 2. Clonar el Repositorio

Descarga el proyecto desde GitHub y navega al directorio recién creado.

```bash
git clone https://github.com/usuario/Nextfin_JA.git
cd Nextfin_JA
```
*(Reemplaza la URL si tu repositorio es diferente)*

### 3. Preparar los Scripts

Es crucial asegurarse de que los scripts tengan el formato de final de línea correcto (LF) para evitar errores en Linux.

```bash
# Convierte los archivos principales
dos2unix setup.sh .env docker-compose.yml

# Opcional: convierte todos los scripts en la carpeta scripts
dos2unix scripts/*.sh
```

### 4. Dar Permisos de Ejecución

El script principal necesita permisos para poder ser ejecutado.

```bash
chmod +x setup.sh
```

### 5. Ejecutar la Instalación

Este es el paso final. El script te guiará, instalará las herramientas necesarias y configurará todo el stack. Se requiere `sudo` porque el script necesita crear directorios, asignar permisos y gestionar los servicios de Docker.

```bash
sudo ./setup.sh
```
> **Nota:** Durante la instalación, el script puede pedirte autorización para instalar herramientas como Docker, Restic, FFmpeg, etc. Confirma cuando sea necesario. Para una instalación totalmente desatendida, puedes usar la bandera `--assume-yes`: `sudo ./setup.sh --assume-yes`.

---

## 🛠️ Post-Instalación

Una vez que el script finalice, tendrás acceso a:

- **Nextcloud:** `http://<tu-ip-o-dominio>:<puerto>`
- **Jellyfin:** `http://<tu-ip-o-dominio>:<puerto>`
- **OnlyOffice:** `http://<tu-ip-o-dominio>:<puerto>`

Las credenciales de administrador y las URLs exactas se mostrarán en la terminal al final del proceso de instalación.

## 🧰 Uso de Scripts Adicionales

El proyecto incluye scripts en la carpeta `/scripts` para tareas de mantenimiento:

- **`backup.sh`:** Crea una copia de seguridad incremental de todos tus datos (Nextcloud, Jellyfin, bases de datos, etc.).
  ```bash
  sudo /ruta/a/tu/proyecto/scripts/backup.sh
  ```
- **`restore.sh`:** Restaura tus datos desde una copia de seguridad existente.
- **`optimizer_images.sh`:** Herramienta interactiva para estandarizar y optimizar imágenes.
- **`optimizer_videos.sh`:** Herramienta interactiva para estandarizar y optimizar videos.

## 📂 Estructura del Proyecto

- **`.env`:** Archivo de configuración principal. **Aquí defines tus contraseñas, rutas y dominios.**
- **`docker-compose.yml`:** Define todos los servicios que se ejecutarán.
- **`setup.sh`:** Script de instalación y configuración inicial.
- **`/scripts`:** Contiene las herramientas de mantenimiento (backup, restore, optimizadores).
- **`/nextcloud_config`:** Configuraciones generadas para Apache y PHP.
- **`/apache_image`:** Dockerfile para construir una imagen de Apache personalizada.
