# Sistema de Infraestructura IoT con ThingsBoard CE

## Información del Proyecto

**Institución:** Universidad Nacional de Colombia  
**Programa:** Pregrado en Ingeniería Electrónica  
**Proyecto:** Wi-Fi-HaLow-IoT-Telemetry-Gateway-for-DLMS-COSEM-Smart-Meters  
**Autor(es):** Brayan Ricardo Pisso Ramírez  
**Director:** Gustavo Adolfo Osorio Londoño  
**Año:** 2025

---

## Tabla de Contenidos

- [Descripción General](#-descripción-general)
- [Arquitectura del Sistema](#-arquitectura-del-sistema)
- [Requisitos del Sistema](#-requisitos-del-sistema)
- [Instalación](#-instalación)
- [Configuración](#-configuración)
- [Ejecución y Uso](#-ejecución-y-uso)
- [Gestión del Sistema](#-gestión-del-sistema)
- [Estructura del Proyecto](#-estructura-del-proyecto)
- [Solución de Problemas](#-solución-de-problemas)
- [Seguridad y SSL/TLS](#-seguridad-y-ssltls)
- [Referencias](#-referencias)

---

## Descripción General

Este proyecto implementa una **plataforma de infraestructura IoT (Internet of Things)** basada en **ThingsBoard Community Edition** utilizando contenedores Docker. La plataforma está diseñada para recibir, procesar, almacenar y visualizar datos de telemetría provenientes de dispositivos IoT, específicamente medidores inteligentes (Smart Meters).

### Características Principales

- **Servidor ThingsBoard CE 4.2.1** - Plataforma IoT completa con interfaz web
- **Base de Datos PostgreSQL 16** - Almacenamiento persistente de datos
- **Sistema de Mensajería Kafka 4.0** - Procesamiento asíncrono de eventos
- **Soporte Multi-Protocolo** - MQTT, LwM2M/CoAP, HTTP REST API
- **Alta Disponibilidad** - Reinicio automático de servicios
- **Seguridad SSL/TLS** - Certificados para comunicación cifrada (opcional)
- **Gestión Simplificada** - Scripts shell para operaciones comunes

### Protocolos Soportados

| Protocolo | Puerto | Descripción | Uso Principal |
|-----------|--------|-------------|---------------|
| **HTTP** | 8080 | Interfaz web y REST API | Administración y visualización |
| **MQTT** | 1883 | Mensajería sin cifrar | Dispositivos IoT con WiFi |
| **MQTTs** | 8883 | MQTT con SSL/TLS | Comunicación segura |
| **LwM2M** | 5683/UDP | Lightweight M2M (CoAP) | Smart Meters y sensores |
| **LwM2M Bootstrap** | 5687/UDP | Configuración automática | Provisioning de dispositivos |

---

## Arquitectura del Sistema

### Diagrama de Componentes

<img width="794" height="856" alt="Arquitectura interna de la capa de plataforma IoT drawio (7)" src="https://github.com/user-attachments/assets/cb408a14-444b-47c0-803f-0955ee66a273" />

### Descripción de Componentes

#### 1. ThingsBoard CE (Community Edition)
- **Función:** Servidor principal IoT que gestiona dispositivos, procesa datos y proporciona visualización
- **Versión:** 4.2.1
- **Imagen Docker:** `thingsboard/tb-node:4.2.1`
- **Características:**
  - Motor de reglas (Rule Engine) para procesamiento en tiempo real
  - Interfaz web para administración y visualización
  - API REST para integración con sistemas externos
  - Soporte para múltiples protocolos IoT

#### 2. PostgreSQL
- **Función:** Base de datos relacional para almacenamiento persistente
- **Versión:** 16
- **Imagen Docker:** `postgres:16`
- **Almacena:**
  - Metadatos de dispositivos
  - Series temporales de telemetría
  - Configuración del sistema
  - Usuarios y permisos
  - Dashboards y widgets

#### 3. Kafka
- **Función:** Sistema de mensajería para procesamiento asíncrono
- **Versión:** 4.0 (KRaft - sin Zookeeper)
- **Imagen Docker:** `bitnamilegacy/kafka:4.0`
- **Beneficios:**
  - Desacoplamiento entre recepción y procesamiento
  - Tolerancia a fallos y recuperación de mensajes
  - Escalabilidad horizontal
  - Procesamiento de alto throughput

---

## Requisitos del Sistema

### Hardware Mínimo

- **CPU:** 2 cores (4 cores recomendado)
- **RAM:** 4 GB (8 GB recomendado para producción)
- **Disco:** 20 GB de espacio libre (SSD recomendado)
- **Red:** Tarjeta Ethernet para comunicación con dispositivos

### Software Requerido

#### Sistema Operativo
- Ubuntu 20.04 LTS o superior (recomendado)
- Debian 11+
- CentOS 8+
- macOS 11+ (para desarrollo)
- Windows 10/11 con WSL2

#### Dependencias Obligatorias

1. **Docker Engine**
   - Versión mínima: 20.10.0
   - Versión recomendada: 24.0.0+
   - [Guía de instalación oficial](https://docs.docker.com/engine/install/)

2. **Docker Compose**
   - Versión mínima: 2.0.0
   - Plugin integrado en Docker Desktop
   - [Guía de instalación](https://docs.docker.com/compose/install/)

#### Herramientas Opcionales (pero recomendadas)

- **mosquitto-clients:** Para pruebas de conectividad MQTT
  ```bash
  sudo apt-get install mosquitto-clients
  ```

- **netcat (nc):** Para verificar puertos
  ```bash
  sudo apt-get install netcat
  ```

- **curl:** Para pruebas de API REST
  ```bash
  sudo apt-get install curl
  ```

### Puertos Requeridos

Asegúrate de que los siguientes puertos estén **libres** (no utilizados por otros servicios):

| Puerto | Protocolo | Servicio | Crítico |
|--------|-----------|----------|---------|
| 8080 | TCP | ThingsBoard HTTP | Sí |
| 1883 | TCP | MQTT | Sí |
| 5683 | UDP | LwM2M CoAP | Opcional |
| 5687 | UDP | LwM2M Bootstrap | Opcional |
| 8883 | TCP | MQTTs (SSL) | Opcional |
| 9092 | TCP | Kafka | Sí |
| 5432 | TCP | PostgreSQL | Sí |

**Verificar puertos libres:**
```bash
# Ver si los puertos están en uso
sudo ss -tulnp | grep -E "8080|1883|9092|5432"
```

---

## Instalación

### Paso 1: Instalar Docker y Docker Compose

#### En Ubuntu/Debian:

```bash
# Actualizar índice de paquetes
sudo apt-get update

# Instalar dependencias
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Agregar clave GPG oficial de Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Configurar repositorio
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Agregar usuario actual al grupo docker (evita usar sudo)
sudo usermod -aG docker $USER

# Aplicar cambios de grupo (o reiniciar sesión)
newgrp docker

# Verificar instalación
docker --version
docker compose version
```

### Paso 2: Clonar o Descargar el Proyecto

```bash
# Opción A: Si tienes acceso al repositorio Git
git clone https://github.com/BRAYANPISSO02/Wi-Fi-HaLow-IoT-Telemetry-Gateway-for-DLMS-COSEM-Smart-Meters.git
cd Wi-Fi-HaLow-IoT-Telemetry-Gateway-for-DLMS-COSEM-Smart-Meters/thingsboard_telemetry_docker

# Opción B: Si tienes el proyecto como archivo
unzip Wi-Fi-HaLow-IoT-Telemetry-Gateway-for-DLMS-COSEM-Smart-Meters.zip
cd Wi-Fi-HaLow-IoT-Telemetry-Gateway-for-DLMS-COSEM-Smart-Meters/thingsboard_telemetry_docker
```

### Paso 3: Estructura del Proyecto

Verifica que la estructura sea correcta:

```bash
tree -L 2 thingsboard_telemetry_visualization/
```

Deberías ver:
```
thingsboard_telemetry_visualization/
├── docker-compose.yml         # Configuración de servicios
├── up.sh                      # Script de inicio
├── down.sh                    # Script de detención
├── install.sh                 # Inicialización de BD
├── logs.sh                    # Ver logs
├── status.sh                  # Ver estado
├── reset.sh                   # Reinicio completo
├── generate-certs.sh          # Generar certificados SSL
├── check-ssl.sh               # Verificar SSL
├── certs/                     # Directorio de certificados
└── README.md                  # Documentación específica
```

---

## Configuración

### Configuración Básica (Predeterminada)

El sistema viene **pre-configurado** con valores por defecto que funcionan para la mayoría de casos. No requiere cambios para iniciar.

**Configuración incluida:**
- Base de datos: `thingsboard` / Usuario: `postgres` / Password: `postgres`
- Kafka en modo KRaft (sin Zookeeper)
- Puertos estándar de ThingsBoard
- Reinicio automático habilitado en todos los servicios

### Configuración Avanzada (Opcional)

Si necesitas modificar configuraciones, edita el archivo `docker-compose.yml`:

```bash
cd thingsboard_telemetry_visualization
nano docker-compose.yml
```

#### Cambiar Puerto de la Interfaz Web

```yaml
# Línea ~47 en docker-compose.yml
ports:
  - "8080:8080"  # Cambiar primer número: "NUEVO_PUERTO:8080"
```

Ejemplo para usar puerto 9090:
```yaml
ports:
  - "9090:8080"
```

#### Cambiar Credenciales de PostgreSQL

```yaml
# Líneas ~7-9 en docker-compose.yml
environment:
  POSTGRES_DB: thingsboard          # Nombre de la BD
  POSTGRES_PASSWORD: tu_password    # Cambiar aquí
```

**Importante:** Si cambias el password, también cámbialo en:
```yaml
# Línea ~65
SPRING_DATASOURCE_PASSWORD: tu_password
```

#### Habilitar SSL/TLS (Producción)

```yaml
# Líneas ~70-75
SSL_ENABLED: true                        # Cambiar de false a true
MQTT_SSL_ENABLED: true                   # Habilitar MQTTs
```

**Nota:** Primero debes generar certificados (ver sección de Seguridad).

### Configuración de Reinicio Automático

El reinicio automático está **habilitado por defecto** en todos los servicios:

```yaml
services:
  postgres:
    restart: always      # Reinicio automático
  kafka:
    restart: always      # Reinicio automático
  thingsboard-ce:
    restart: always      # Reinicio automático
```

**Opciones de política de reinicio:**

| Política | Comportamiento |
|----------|----------------|
| `no` | Nunca reinicia automáticamente |
| `always` | Siempre reinicia (incluso tras reinicio del host) |
| `on-failure` | Solo reinicia si falla (exit code != 0) |
| `unless-stopped` | Reinicia excepto si fue detenido manualmente |

**Recomendación:** Mantener `always` para alta disponibilidad.

---

## Ejecución y Uso

### Inicio del Sistema (Primera Vez)

#### Paso 1: Navegar al directorio del proyecto

```bash
cd /ruta/al/proyecto/thingsboard_telemetry_docker/thingsboard_telemetry_visualization
```

#### Paso 2: Hacer los scripts ejecutables (solo primera vez)

```bash
chmod +x *.sh
```

#### Paso 3: Iniciar los contenedores

```bash
./up.sh
```

**Salida esperada:**
```
[up] Checking required host TCP ports: 8080 7070 1883 8883 9092
[up] Checking required UDP port range: 5683-5688
Starting ThingsBoard CE stack (Postgres + Kafka + tb-node) ...
[+] Running 4/4
 ✔ Network thingsboard_default             Created
 ✔ Container thingsboard-postgres-1        Started
 ✔ Container thingsboard-kafka-1           Started
 ✔ Container thingsboard-thingsboard-ce-1  Started
REST/API (and UI if present): http://localhost:8080
Kafka (host): localhost:9092
```

#### Paso 4: Inicializar la base de datos

**Solo la primera vez o después de un reset:**

```bash
# Opción A: Sin datos de demostración (recomendado para producción)
./install.sh

# Opción B: Con datos de demostración (útil para pruebas)
./install.sh --demo
```

**Proceso de instalación:**
```
[thingsboard] Install start (demo=false force=0 wait=0 timeout=180s)
[+] Running 1/0
 ✔ Container thingsboard-thingsboard-ce-1  Created
Installing ThingsBoard (this may take 2-3 minutes)...
ThingsBoard installed successfully!
[thingsboard] Install finished.
```

**Tiempo de instalación:** 2-5 minutos dependiendo del hardware.

#### Paso 5: Verificar que todo esté funcionando

```bash
./status.sh
```

**Salida esperada (todos en estado "Up"):**
```
NAME                              STATUS          PORTS
thingsboard-thingsboard-ce-1      Up 2 minutes    0.0.0.0:8080->8080/tcp, ...
thingsboard-postgres-1            Up 2 minutes    0.0.0.0:5432->5432/tcp
thingsboard-kafka-1               Up 2 minutes    0.0.0.0:9092->9092/tcp
```

### Acceso a la Interfaz Web

#### Paso 1: Abrir navegador

```
URL: http://localhost:8080
```

**Nota:** Si cambiaste el puerto en la configuración, usa ese puerto.

#### Paso 2: Iniciar sesión

**Credenciales por defecto:**

| Rol | Email | Password | Descripción |
|-----|-------|----------|-------------|
| **System Administrator** | `sysadmin@thingsboard.org` | `sysadmin` | Administración completa del sistema |
| **Tenant Administrator** | `tenant@thingsboard.org` | `tenant` | Administración del tenant (recomendado) |
| **Customer User** | `customer@thingsboard.org` | `customer` | Usuario final (solo lectura) |

**SEGURIDAD:** Cambia estas contraseñas inmediatamente en producción.

#### Paso 3: Explorar la interfaz

- **Dashboard:** Visualización de datos
- **Devices:** Gestión de dispositivos IoT
- **Assets:** Jerarquía de activos
- **Rule Chains:** Configuración de reglas de procesamiento
- **Customers:** Gestión de clientes/usuarios

### Reinicio del Sistema

#### Después de Reiniciar el Servidor/PC

**No requiere acción manual.** El sistema se inicia automáticamente gracias a la política `restart: always`.

**Verificación:**
```bash
docker ps | grep thingsboard
```

#### Reinicio Manual (Si es Necesario)

```bash
# Opción 1: Reiniciar solo ThingsBoard
docker restart thingsboard-thingsboard-ce-1

# Opción 2: Reiniciar todo el stack
cd thingsboard_telemetry_visualization
./down.sh
./up.sh
```

### Detener el Sistema

```bash
cd thingsboard_telemetry_visualization
./down.sh
```

**Esto detiene los contenedores pero NO borra los datos.**

**Datos que permanecen:**
- Base de datos PostgreSQL (volumen `tb-postgres-data`)
- Datos de Kafka (volumen `tb-ce-kafka-data`)
- Configuración del sistema
- Dispositivos registrados
- Dashboards creados

---

## Gestión del Sistema

### Comandos de Operación Diaria

#### Ver Logs en Tiempo Real

```bash
cd thingsboard_telemetry_visualization

# Ver logs de ThingsBoard
./logs.sh

# Ver logs de un servicio específico
docker compose logs -f postgres
docker compose logs -f kafka

# Ver últimas 50 líneas
docker compose logs --tail 50 thingsboard-ce
```

**Atajos de teclado en logs:**
- `Ctrl + C`: Salir de los logs
- `Shift + PageUp/PageDown`: Desplazarse

#### Verificar Estado de Servicios

```bash
./status.sh
```

**Interpretación de estados:**
- `Up X minutes (healthy)`: Servicio funcionando correctamente
- `Up X minutes`: Servicio iniciado pero sin healthcheck
- `Restarting`: Servicio reiniciándose (posible problema)
- `Exited (1)`: Servicio detenido con error

---

## Estructura del Proyecto

```
Wi-Fi-HaLow-IoT-Telemetry-Gateway-for-DLMS-COSEM-Smart-Meters/
└── thingsboard_telemetry_docker/
    ├── README_PROYECTO_GRADO.md               # Este archivo
    ├── QUE_HAY_REALMENTE.md                   # Documentación de componentes
    │
    └── thingsboard_telemetry_visualization/   # Directorio principal
        ├── docker-compose.yml                 # Configuración de servicios
        ├── up.sh                              # Iniciar sistema
        ├── down.sh                            # Detener sistema
        ├── install.sh                         # Inicializar BD
        ├── logs.sh                            # Ver logs
        ├── status.sh                          # Ver estado
        ├── reset.sh                           # Reinicio completo
        ├── generate-certs.sh                  # Generar certificados
        ├── check-ssl.sh                       # Verificar SSL
        └── certs/                             # Certificados SSL
```

---

## Solución de Problemas

Ver documento completo en el archivo principal del proyecto.

---

## Seguridad y SSL/TLS

Ver sección de seguridad en el documento principal.

---

## Referencias

### Documentación Oficial

- [ThingsBoard Documentation](https://thingsboard.io/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

## Contacto

**Autor:** BRAYAN RICARDO PISSO RAMÍREZ  
**Email:** bpisso@unal.edu.co 
**Universidad:** UNIVERSIDAD NACIONAL DE COLOMBIA - SEDE MANIZALES  

---

**Última actualización:** 21 de noviembre de 2025  
**Versión:** 1.0
