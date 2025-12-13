# Puente TCP/IP a RS485 sobre WiFi (ESP32-C6)

Este repositorio contiene el firmware para un dispositivo **Gateway IoT** desarrollado sobre el SoC **ESP32-C6** (arquitectura RISC-V). El sistema actúa como un puente transparente bidireccional entre una red **TCP/IP** y un bus de campo industrial **RS485**, permitiendo la integración de sensores, actuadores o PLCs antiguos en infraestructuras de red modernas inalámbricas (WiFi).

Este proyecto forma parte del Trabajo de Grado para la obtención del título de [Tu Título].

## Descripción General

El firmware levanta un servidor TCP en el ESP32-C6 que escucha conexiones entrantes. Al establecerse una conexión, cualquier dato enviado por el cliente TCP se transmite físicamente al bus RS485, gestionando automáticamente el control de dirección (Half-Duplex). Inversamente, cualquier respuesta en el bus RS485 es retransmitida al cliente TCP conectado.

### Características Técnicas
*   **SoC:** ESP32-C6 (Soporte WiFi 6 / 2.4GHz).
*   **S.O.:** FreeRTOS (ESP-IDF).
*   **Protocolo de Red:** TCP Server (Socket Stream).
*   **Protocolo Serial:** UART RS485 (Half-Duplex con control DE/RE).
*   **Gestión de Configuración:** WiFi Provisioning vía SoftAP (Aplicación móvil).
*   **Almacenamiento:** Persistencia de credenciales en NVS (Non-Volatile Storage).
*   **Seguridad:** Timeout de inactividad (30s) para liberación de sockets huérfanos.

<img width="781" height="641" alt="Arquitectura interna de la capa de transmisión drawio (1)" src="https://github.com/user-attachments/assets/24b695db-cd00-43af-ab27-ab174080f679" />

## Hardware y Pinout

Se requiere un módulo transceptor RS485 (ej. MAX485 o MAX3485) para la conversión de niveles lógicos TTL a diferenciales.

| Pin ESP32-C6 | Nombre en Código | Conexión Módulo RS485 | Función |
| :--- | :--- | :--- | :--- |
| **GPIO 22** | `UART_TX_PIN` | **DI** (Driver Input) | Transmisión de Datos |
| **GPIO 23** | `UART_RX_PIN` | **RO** (Receiver Output)| Recepción de Datos |
| **GPIO 02** | `UART_DE_RE_PIN` | **DE** y **RE** | Control de Flujo (Habilitación) |
| **GPIO 15** | `ACTIVITY_PIN` | LED (Ánodo/Cátodo*) | Indicador de Estado/Actividad |
| **GND** | - | **GND** | Tierra Común |
| **3V3 / 5V** | - | **VCC** | Alimentación Transceptor |

> **Nota sobre el LED:** El pin de actividad está configurado con lógica invertida (`SET_OFF` activa el LED en configuraciones *sink* o apaga en *source* dependiendo del circuito, ajustado para indicar actividad durante la transmisión).

## Configuración del Sistema

### Parámetros de Comunicación
*   **Puerto TCP:** `3333`
*   **Baudrate RS485:** `9600` bps
*   **Configuración Serial:** 8N1 (8 bits de datos, Sin paridad, 1 bit de parada).
*   **Timeout de Inactividad:** 30 segundos.

## Guía de Uso

### 1. Provisionamiento WiFi (Primera vez)
Al flashear el dispositivo por primera vez o tras un borrado completo, este no tendrá credenciales WiFi:
1.  El dispositivo iniciará en modo **APSTA** (Access Point + Station).
2.  Generará una red WiFi llamada: `MyDeviceAP`.
3.  Conéctese a ella usando su smartphone.
4.  Utilice la App **ESP SoftAP Provisioning** (disponible para Android/iOS).
5.  Ingrese el código de prueba (POP): `123`.
6.  Envíe el SSID y Contraseña de su red local.
7.  El ESP32 guardará los datos en NVS y se reiniciará en modo **Station (STA)**.

### 2. Operación Normal
1.  El dispositivo se conecta a la red WiFi configurada.
2.  Inicia el servidor TCP en el puerto **3333**.
3.  Conéctese desde un PC usando un cliente TCP (Packet Sender, Putty, Hercules) a la IP asignada al ESP32.
4.  Envíe tramas de datos:
    *   **TCP -> RS485:** Los bytes recibidos por WiFi salen por los pines UART. El LED parpadea brevemente.
    *   **RS485 -> TCP:** Los datos detectados en el bus se envían al socket abierto.

### 3. Estados del LED
*   **Encendido fijo:** Sistema en reposo (Idle) / Esperando conexión.
*   **Apagado momentáneo (Blink):** Transmisión o recepción de datos en curso.

## Arquitectura de Software

El código está estructurado en tareas de FreeRTOS para garantizar el determinismo temporal:

1.  **`app_main`**:
    *   Inicializa NVS, Drivers y Stack TCP/IP.
    *   Gestiona el *Wifi Provisioning Manager*.
    *   Lanza las tareas del sistema.
2.  **`tcp_server_task`**:
    *   Maneja el ciclo de vida del socket (`socket`, `bind`, `listen`, `accept`).
    *   Recibe datos TCP y controla el pin `UART_DE_RE_PIN` para escribir en el bus RS485.
    *   Implementa el *Watchdog* de inactividad de 30s.
3.  **`uart_to_tcp_task`**:
    *   Monitorea el buffer UART mediante interrupciones.
    *   Si hay datos en el bus RS485 y un cliente TCP conectado, reenvía los datos al socket.
    *   Utiliza un `SemaphoreHandle_t` (`tcp_socket_mutex`) para evitar conflictos de escritura/lectura en el socket compartido.

## Solución de Problemas

| Síntoma | Causa Probable | Solución |
| :--- | :--- | :--- |
| **No conecta al WiFi** | Credenciales erróneas o red 5GHz. | Reprovisionar vía SoftAP. Usar red 2.4GHz. |
| **Socket se cierra solo** | Inactividad > 30s. | Enviar datos periódicos ("keep-alive"). |
| **No hay comunicación RS485** | Pines A/B invertidos o Baudrate. | Verificar cableado A con A, B con B. Baudrate 9600. |
| **Mensaje "UART write incomplete"** | Buffer lleno o error eléctrico. | Revisar conexión física y fuente de alimentación. |

## Licencia
Este proyecto se distribuye bajo fines académicos. Basado en ESP-IDF de Espressif Systems.
