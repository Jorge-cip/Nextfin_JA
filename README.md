# Nextcloud + OnlyOffice + Jellyfin Stack (Docker Compose)

## Descripción del Proyecto

Este repositorio contiene una solución completa para desplegar un stack de servicios multimedia y de productividad utilizando Docker Compose. Incluye:

*   **Nextcloud:** Una plataforma de almacenamiento en la nube autoalojada, sincronización y colaboración.
*   **OnlyOffice Document Server:** Un potente editor de documentos online integrado con Nextcloud.
*   **Jellyfin Media Server:** Un servidor multimedia de código abierto para organizar, gestionar y transmitir tus archivos multimedia.

La configuración está optimizada para un entorno de producción, utilizando PHP-FPM y Apache HTTP/2 para Nextcloud, y PostgreSQL y Redis para las bases de datos y el almacenamiento en caché.

## Características Principales

*   **Despliegue Simplificado:** Un único script `setup.sh` automatiza la configuración inicial.
*   **Contenedorización:** Todos los servicios se ejecutan en contenedores Docker aislados.
*   **Optimización de Rendimiento:** Configuración de Apache con HTTP/2, PHP-FPM y Redis para un rendimiento óptimo.
*   **Gestión de Medios:** Scripts personalizados para la optimización y estandarización de imágenes y videos.
*   **Respaldo y Restauración:** Scripts dedicados para realizar copias de seguridad incrementales y restaurar el stack completo.
*   **Permisos Colaborativos:** Configuración de permisos para facilitar la colaboración en carpetas multimedia.

## Requisitos Previos

Asegúrate de tener instalados los siguientes componentes en tu sistema host:

*   **Docker:** Motor de contenedores.
*   **Docker Compose (v2):** Herramienta para definir y ejecutar aplicaciones Docker multi-contenedor.
*   **Restic:** Herramienta de backup.
*   **FFmpeg / FFprobe:** Para procesamiento de video.
*   **ImageMagick (`convert`):** Para procesamiento de imágenes.
*   **`jq`:** Procesador JSON en línea de comandos.
*   **`bc`:** Calculadora de precisión arbitraria.
*   **`wget`:** Descargador de archivos.
*   **`unzip`:** Descompresor de archivos.
*   **`zstd`:** Compresor/descompresor rápido.

## Instalación y Despliegue

Sigue estos pasos para poner en marcha tu stack:

1.  **Clonar el Repositorio:**
    ```bash
    git clone <URL_DE_TU_REPOSITORIO>
    cd <nombre_del_directorio_clonado>
    ```
    (Reemplaza `<URL_DE_TU_REPOSITORIO>` y `<nombre_del_directorio_clonado>` con los valores correctos).

2.  **Configurar el Archivo `.env`:**
    Copia el archivo `.env.example` (si existe, si no, crea uno) y edita las variables de entorno según tus necesidades. Este archivo contendrá las credenciales, rutas de datos y configuraciones de puertos.

    ```bash
    cp .env.example .env # Si tienes un .env.example
    # Edita el archivo .env con tus valores
    nano .env # o tu editor preferido
    ```

3.  **Ejecutar el Script de Configuración:**
    Este script automatizará la creación de directorios, la generación de configuraciones y el despliegue de los contenedores Docker.

    ```bash
    sudo ./setup.sh
    ```
    El script te guiará a través del proceso. La primera ejecución puede tardar un poco mientras se construyen las imágenes Docker.

## Acceso a los Servicios

Una vez que el despliegue se haya completado con éxito, podrás acceder a tus servicios a través de las siguientes URLs (ajusta los puertos y dominios según tu configuración en `.env`):

*   **Nextcloud:** `http://<TU_DOMINIO_O_IP>:<PUERTO_NEXTCLOUD>`
*   **OnlyOffice:** `http://<TU_DOMINIO_O_IP>:<PUERTO_ONLYOFFICE>`
*   **Jellyfin:** `http://<TU_DOMINIO_O_IP>:<PUERTO_JELLYFIN>`

**Credenciales por defecto (configurables en `.env`):**
*   **Usuario Nextcloud:** `admin`
*   **Contraseña Nextcloud:** `tu_contraseña_segura`

## Scripts Importantes

El directorio `scripts/` contiene herramientas esenciales para la gestión de tu stack:

*   **`setup.sh`**:
    *   **Descripción:** El script principal para la configuración inicial y el despliegue de todo el stack. Verifica dependencias, crea directorios, genera archivos de configuración y levanta los servicios Docker.
    *   **Uso:** `sudo ./setup.sh`

*   **`backup.sh`**:
    *   **Descripción:** Realiza una copia de seguridad incremental de tus datos de Nextcloud, OnlyOffice y Jellyfin utilizando Restic. Incluye las bases de datos y los archivos multimedia.
    *   **Uso:** `sudo ./scripts/backup.sh`
    *   **Recomendación:** Programa este script con `cron` para backups automáticos (ej: `sudo crontab -e`).

*   **`restore.sh`**:
    *   **Descripción:** Permite restaurar el stack completo desde un snapshot de Restic. **¡ADVERTENCIA: Esto sobrescribirá los datos existentes!**
    *   **Uso:** `sudo ./scripts/restore.sh`

*   **`optimizer_videos.sh`**:
    *   **Descripción:** Herramienta interactiva para optimizar y estandarizar tus archivos de video. Puede recodificar videos antiguos o con formatos no estándar para mejorar la compatibilidad y el rendimiento en dispositivos como Smart TVs. Mueve los originales a una papelera de reciclaje.
    *   **Uso:** `sudo ./scripts/optimizer_videos.sh`

*   **`optimizer_images.sh`**:
    *   **Descripción:** Herramienta automática para optimizar y escalar tus imágenes a un ancho estándar definido. Ideal para reducir el tamaño de los archivos y acelerar la carga en la web. Mueve los originales a una papelera de reciclaje.
    *   **Uso:** `sudo ./scripts/optimizer_images.sh`

## Notas Adicionales y Próximos Pasos

*   **Aplicación Móvil Nextcloud:** La configuración incluye ajustes para mejorar la compatibilidad con la aplicación móvil de Nextcloud.
*   **Jellyfin:** Considera configurar el monitoreo de bibliotecas en Jellyfin según tus preferencias.
*   **Programación de Backups:** Es altamente recomendable programar el script `backup.sh` para que se ejecute regularmente.

## Desarrollador

Este proyecto fue desarrollado por: **JAAG**
