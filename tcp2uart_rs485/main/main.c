// TCP Server with WiFi connection communication via Socket

#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/timers.h"
#include "freertos/event_groups.h"
#include "freertos/queue.h"

#include "esp_wifi.h"
#include "esp_log.h"
#include "esp_check.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_event.h"
#include "esp_system.h"
#include "esp_timer.h"

#include "lwip/inet.h"
#include "lwip/netdb.h"
#include "lwip/sockets.h"
#include "lwip/ip_addr.h"

#include "nvs_flash.h"
#include "nvs.h"
#include "ping/ping_sock.h"
#include "driver/gpio.h"
#include "driver/uart.h"
#include <ctype.h>  // para isspace()

#include "wifi_provisioning/manager.h"
#include "wifi_provisioning/scheme_softap.h"

#define INACTIVITY_TIMEOUT_MS 30 * 1000
#define PORT 3333
static const char *TAG = "TCP_SOCKET";

#define UART_PORT UART_NUM_1
#define UART_DE_RE_PIN 2
#define UART_TX_PIN 22
#define UART_RX_PIN 23
#define UART_BAUDRATE 9600

#define ACTIVITY_PIN 15
#define DELAY_ACTIVITY_MS 20
#define SET_OFF 0
#define SET_ON 1

#define WIFI_NVS_NAMESPACE "wifi_cfg"
#define WIFI_NVS_KEY_SSID "ssid"
#define WIFI_NVS_KEY_PASS "pass"

int tcp_client_socket = -1;         // socket del cliente TCP conectado
SemaphoreHandle_t tcp_socket_mutex; // protege el acceso al socket

static esp_err_t save_wifi_credentials_to_nvs(const wifi_sta_config_t *sta_cfg)
{
    if (sta_cfg == NULL)
    {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(WIFI_NVS_NAMESPACE, NVS_READWRITE, &handle);
    if (err != ESP_OK)
    {
        ESP_LOGE(TAG, "No se pudo abrir NVS para guardar credenciales: %s", esp_err_to_name(err));
        return err;
    }

    char ssid[sizeof(sta_cfg->ssid) + 1];
    char password[sizeof(sta_cfg->password) + 1];
    memset(ssid, 0, sizeof(ssid));
    memset(password, 0, sizeof(password));

    size_t ssid_len = strnlen((const char *)sta_cfg->ssid, sizeof(sta_cfg->ssid));
    size_t password_len = strnlen((const char *)sta_cfg->password, sizeof(sta_cfg->password));
    memcpy(ssid, sta_cfg->ssid, ssid_len);
    memcpy(password, sta_cfg->password, password_len);

    err = nvs_set_str(handle, WIFI_NVS_KEY_SSID, ssid);
    if (err == ESP_OK)
    {
        err = nvs_set_str(handle, WIFI_NVS_KEY_PASS, password);
    }

    if (err == ESP_OK)
    {
        err = nvs_commit(handle);
    }

    nvs_close(handle);

    if (err == ESP_OK)
    {
        ESP_LOGI(TAG, "Credenciales WiFi guardadas en NVS (SSID: %s)", ssid);
    }
    else
    {
        ESP_LOGE(TAG, "Fallo al guardar credenciales WiFi: %s", esp_err_to_name(err));
    }

    return err;
}

static bool load_wifi_credentials_from_nvs(wifi_config_t *wifi_cfg)
{
    if (wifi_cfg == NULL)
    {
        return false;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(WIFI_NVS_NAMESPACE, NVS_READONLY, &handle);
    if (err != ESP_OK)
    {
        ESP_LOGI(TAG, "No hay credenciales WiFi guardadas en NVS: %s", esp_err_to_name(err));
        return false;
    }

    char ssid[33] = {0};
    char password[65] = {0};
    size_t ssid_len = sizeof(ssid);
    size_t password_len = sizeof(password);

    err = nvs_get_str(handle, WIFI_NVS_KEY_SSID, ssid, &ssid_len);
    if (err == ESP_OK)
    {
        err = nvs_get_str(handle, WIFI_NVS_KEY_PASS, password, &password_len);
    }

    nvs_close(handle);

    if (err != ESP_OK)
    {
        ESP_LOGW(TAG, "Error leyendo credenciales WiFi guardadas: %s", esp_err_to_name(err));
        return false;
    }

    memset(wifi_cfg, 0, sizeof(*wifi_cfg));
    size_t ssid_copy_len = (ssid_len > 0) ? (ssid_len - 1) : 0;
    size_t password_copy_len = (password_len > 0) ? (password_len - 1) : 0;
    memcpy(wifi_cfg->sta.ssid, ssid, ssid_copy_len);
    memcpy(wifi_cfg->sta.password, password, password_copy_len);

    ESP_LOGI(TAG, "Credenciales WiFi cargadas de NVS (SSID: %s)", ssid);
    return true;
}

// Convierte string con hex en bytes reales
int hexstr_to_bytes(const char *hexstr, uint8_t *buf, int bufsize) {
    int len = 0;
    while (*hexstr && len < bufsize) {
        while (isspace((unsigned char)*hexstr)) hexstr++;  // saltar espacios

        if (!isxdigit((unsigned char)hexstr[0]) || !isxdigit((unsigned char)hexstr[1])) {
            break; // fin si no hay 2 hex válidos
        }

        unsigned int byte;
        sscanf(hexstr, "%2x", &byte);
        buf[len++] = (uint8_t)byte;
        hexstr += 2;
    }
    return len; // número de bytes convertidos
}

static void tcp_server_task(void *pvParameters)
{
    struct sockaddr_in dest_addr;
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    dest_addr.sin_port = htons(PORT);

    int listen_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(listen_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    bind(listen_sock, (struct sockaddr *)&dest_addr, sizeof(dest_addr));
    listen(listen_sock, 1);

    while (1)
    {
        ESP_LOGI(TAG, "Waiting for client...");
        struct sockaddr_in client_addr;
        socklen_t addr_len = sizeof(client_addr);

        int client_sock = accept(listen_sock, (struct sockaddr *)&client_addr, &addr_len);
        if (client_sock < 0)
        {
            ESP_LOGE(TAG, "accept failed: errno %d", errno);
            continue;
        }

        char client_ip[32];
        inet_ntoa_r(client_addr.sin_addr, client_ip, sizeof(client_ip));
        ESP_LOGI(TAG, "Client connected: %s", client_ip);

        xSemaphoreTake(tcp_socket_mutex, portMAX_DELAY);
        tcp_client_socket = client_sock;
        xSemaphoreGive(tcp_socket_mutex);

        int64_t last_activity = esp_timer_get_time(); // microsegundos

        char tcp_buffer[128];
        int len;

        fcntl(client_sock, F_SETFL, fcntl(client_sock, F_GETFL, 0) | O_NONBLOCK);

        while (1)
        {
            len = recv(client_sock, tcp_buffer, sizeof(tcp_buffer) - 1, 0);
            if (len > 0)
            {
                /* No modificar el formato: enviar tal cual los bytes recibidos por TCP al UART */
                last_activity = esp_timer_get_time(); // actualizar actividad
                ESP_LOGI(TAG, "TCP/IP --> RS485 | Len: %d bytes", len);

                gpio_set_level(ACTIVITY_PIN, SET_OFF);
                gpio_set_level(UART_DE_RE_PIN, SET_ON);
                vTaskDelay(1 / portTICK_PERIOD_MS);
                int uart_len = uart_write_bytes(UART_NUM_1, (const char *)tcp_buffer, len);

                if (uart_len != len)
                {
                    ESP_LOGW(TAG, "UART write incomplete: %d/%d", uart_len, len);
                }

                uart_wait_tx_done(UART_NUM_1, pdMS_TO_TICKS(100));
                gpio_set_level(UART_DE_RE_PIN, SET_OFF);
                vTaskDelay(DELAY_ACTIVITY_MS / portTICK_PERIOD_MS);
                gpio_set_level(ACTIVITY_PIN, SET_ON);
            }
            else if (len == 0)
            {
                ESP_LOGI(TAG, "Client disconnected");
                break;
            }
            else if (errno != EAGAIN && errno != EWOULDBLOCK)
            {
                ESP_LOGE(TAG, "recv error: %d", errno);
                break;
            }

            // printf("now: %d us last: %d us diff: %d\r\n ms", (int)esp_timer_get_time(), (int)last_activity, (int)(esp_timer_get_time() - last_activity) / 1000);

            // timeout de inactividad
            if ((esp_timer_get_time() - last_activity) / 1000 > INACTIVITY_TIMEOUT_MS)
            {
                ESP_LOGI(TAG, "Closing socket due to inactivity");

                gpio_set_level(ACTIVITY_PIN, SET_OFF);
                // Servidor (ESP32) envía comando
                char close_msg_0[128]; // buffer para el mensaje
                sprintf(close_msg_0, "Closing socket due to inactivity (%d sec)\n", INACTIVITY_TIMEOUT_MS / 1000);
                send(client_sock, close_msg_0, strlen(close_msg_0), 0);
                vTaskDelay(100 / portTICK_PERIOD_MS);
                const char *close_msg_1 = "CLOSE";
                send(client_sock, close_msg_1, strlen(close_msg_1), 0);
                gpio_set_level(ACTIVITY_PIN, SET_ON);

                break;
            }

            vTaskDelay(100 / portTICK_PERIOD_MS);
        }

        xSemaphoreTake(tcp_socket_mutex, portMAX_DELAY);
        close(tcp_client_socket);
        tcp_client_socket = -1;
        xSemaphoreGive(tcp_socket_mutex);
    }

    close(listen_sock);
    vTaskDelete(NULL);
}

static void wifi_event_handler(void *event_handler_arg, esp_event_base_t event_base, int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT)
    {
        switch (event_id)
        {
        case WIFI_EVENT_STA_START:
            ESP_LOGI(TAG, "WiFi STA iniciado, intentando conectar...");
            if (esp_wifi_connect() != ESP_OK)
            {
                ESP_LOGW(TAG, "No se pudo iniciar la conexión WiFi en este momento, se volverá a intentar");
            }
            break;
        case WIFI_EVENT_STA_CONNECTED:
            ESP_LOGI(TAG, "WiFi conectado al AP");
            break;
        case WIFI_EVENT_STA_DISCONNECTED:
        {
            wifi_event_sta_disconnected_t *disconnected = (wifi_event_sta_disconnected_t *)event_data;
            ESP_LOGW(TAG, "WiFi desconectado, reason=%d. Reintentando...", disconnected ? disconnected->reason : -1);
            esp_err_t err = esp_wifi_connect();
            if (err != ESP_OK)
            {
                ESP_LOGE(TAG, "Fallo reintentando la conexión WiFi: %s", esp_err_to_name(err));
            }
            break;
        }
        default:
            break;
        }
    }
    else if (event_base == IP_EVENT)
    {
        if (event_id == IP_EVENT_STA_GOT_IP)
        {
            ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
            ESP_LOGI(TAG, "WiFi obtuvo IP: " IPSTR, IP2STR(&event->ip_info.ip));
        }
    }
}

// ------------------- UART -------------------

static void uart_to_tcp_task(void *pvParameters)
{
    char uart_buffer[128];

    while (1)
    {
        // ESP_LOGI(TAG, "Witing data from UART...");

        int len = uart_read_bytes(UART_PORT, (uint8_t *)uart_buffer, sizeof(uart_buffer) - 1, 100 / portTICK_PERIOD_MS);
        if (len > 0)
        {
            uart_buffer[len] = 0;

            xSemaphoreTake(tcp_socket_mutex, portMAX_DELAY);
            if (tcp_client_socket != -1)
            {
                gpio_set_level(ACTIVITY_PIN, SET_OFF);
                send(tcp_client_socket, uart_buffer, len, 0);
                ESP_LOGI(TAG, "RS485 --> TCP/IP | Len: %d bytes | Data: %s ", len, uart_buffer);
                vTaskDelay(DELAY_ACTIVITY_MS / portTICK_PERIOD_MS);
                gpio_set_level(ACTIVITY_PIN, SET_ON);
            }
            else
            {
                ESP_LOGW(TAG, "No TCP client connected, cannot send data");

                // Enviar inmediatamente por UART
                gpio_set_level(ACTIVITY_PIN, SET_OFF);
                gpio_set_level(UART_DE_RE_PIN, SET_ON);
                vTaskDelay(1 / portTICK_PERIOD_MS);
                const char buffer_uart_warning[] = "\n\rNo TCP client connected, cannot send data\n\r";
                int len_uart_warning = strlen(buffer_uart_warning);
                uart_write_bytes(UART_NUM_1, (const char *)buffer_uart_warning, len_uart_warning);
                uart_wait_tx_done(UART_NUM_1, pdMS_TO_TICKS(100));
                gpio_set_level(UART_DE_RE_PIN, SET_OFF);
                vTaskDelay(DELAY_ACTIVITY_MS / portTICK_PERIOD_MS);
                gpio_set_level(ACTIVITY_PIN, SET_ON);
            }
            xSemaphoreGive(tcp_socket_mutex);
        }
    }
}

static void uart_init(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = 1ULL << UART_DE_RE_PIN,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE};
    gpio_config(&io_conf);

    // Inicialmente en modo recepción
    gpio_set_level(UART_DE_RE_PIN, SET_OFF);

    const uart_config_t uart_config = {
        .baud_rate = UART_BAUDRATE,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE};
    ESP_ERROR_CHECK(uart_driver_install(UART_PORT, 2048, 2048, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(UART_PORT, &uart_config));
    ESP_ERROR_CHECK(uart_set_pin(UART_PORT, UART_TX_PIN, UART_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
    ESP_LOGI(TAG, "UART inicializado en TX=%d, RX=%d, baud=%d", UART_TX_PIN, UART_RX_PIN, UART_BAUDRATE);
}

/* Handler de eventos del provisioning BLE / manager */
static void provision_event_handler(void *user_data, wifi_prov_cb_event_t event, void *event_data)
{
    switch (event)
    {
    case WIFI_PROV_INIT:
        ESP_LOGI(TAG, "Provisioning initialized");
        break;
    case WIFI_PROV_START:
        ESP_LOGI(TAG, "Provisioning service started");
        break;
    case WIFI_PROV_CRED_RECV:
    {
        wifi_sta_config_t *wifi_cfg = (wifi_sta_config_t *)event_data;
        ESP_LOGI(TAG, "Received WiFi credentials: SSID = %s, password = %s",
                 (const char *)wifi_cfg->ssid, (const char *)wifi_cfg->password);
        break;
    }
    case WIFI_PROV_CRED_FAIL:
    {
        wifi_prov_sta_fail_reason_t *reason = (wifi_prov_sta_fail_reason_t *)event_data;
        ESP_LOGE(TAG, "Provisioning failed, reason: %s",
                 (*reason == WIFI_PROV_STA_AUTH_ERROR) ? "WiFi auth error" : "WiFi AP not found");
        break;
    }
    case WIFI_PROV_CRED_SUCCESS:
        ESP_LOGI(TAG, "Provisioning successful");
        {
            wifi_config_t current_cfg;
            if (esp_wifi_get_config(WIFI_IF_STA, &current_cfg) == ESP_OK)
            {
                save_wifi_credentials_to_nvs(&current_cfg.sta);
            }
            else
            {
                ESP_LOGW(TAG, "No se pudo obtener la configuración WiFi tras el provisioning");
            }
        }
        break;
    case WIFI_PROV_END:
        ESP_LOGI(TAG, "Provisioning end event");
        break;
    case WIFI_PROV_DEINIT:
        ESP_LOGI(TAG, "Provisioning deinitialized");
        break;
    default:
        break;
    }
}

void app_main(void)
{

    gpio_config_t io_conf = {
        .pin_bit_mask = 1ULL << ACTIVITY_PIN,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE};
    gpio_config(&io_conf);

    gpio_set_level(ACTIVITY_PIN, SET_OFF);

    esp_err_t err;

    // 1. Inicializar NVS (necesario para WiFi / provisioning)
    err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND)
    {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    // 2. Inicializar el loop de eventos y el stack TCP/IP
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    // Crear interfaces de red para AP y STA
    esp_netif_create_default_wifi_ap();
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL));

    // Inicializar el manager de provisioning
    wifi_prov_mgr_config_t prov_config = {
        .scheme = wifi_prov_scheme_softap,
        .scheme_event_handler = WIFI_PROV_EVENT_HANDLER_NONE,
        .app_event_handler = {
            .event_cb = provision_event_handler,
            .user_data = NULL}};
    ESP_ERROR_CHECK(wifi_prov_mgr_init(prov_config));

    bool provisioned = false;
    ESP_ERROR_CHECK(wifi_prov_mgr_is_provisioned(&provisioned));

    wifi_config_t stored_cfg;
    bool has_stored_cfg = load_wifi_credentials_from_nvs(&stored_cfg);

    if (!provisioned && !has_stored_cfg)
    {
        ESP_LOGI(TAG, "Sin credenciales en NVS, iniciando provisioning SoftAP");
        ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));

        wifi_config_t ap_cfg = {
            .ap = {
                .ssid = "MyDeviceAP",
                .ssid_len = strlen("MyDeviceAP"),
                .password = "",
                .channel = 1,
                .max_connection = 4,
                .authmode = WIFI_AUTH_OPEN // abierto para provisioning
            },
        };
        ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap_cfg));
        ESP_ERROR_CHECK(esp_wifi_start());

        wifi_prov_security_t security = WIFI_PROV_SECURITY_1;
        const char *pop = "123";
        const char *service_name = "PROV_PCI";
        const char *service_key = NULL;

        ESP_ERROR_CHECK(wifi_prov_mgr_start_provisioning(security, (void *)pop,
                                                         service_name, service_key));

        wifi_prov_mgr_wait();
        wifi_prov_mgr_deinit();

        wifi_config_t new_cfg;
        if (esp_wifi_get_config(WIFI_IF_STA, &new_cfg) == ESP_OK)
        {
            save_wifi_credentials_to_nvs(&new_cfg.sta);
        }

        ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
        if (esp_wifi_connect() != ESP_OK)
        {
            ESP_LOGW(TAG, "Reintento de conexión inicial tras provisioning programado por manejador de eventos");
        }
        ESP_LOGI(TAG, "Provisioning finalizado, dispositivo en modo STA");
    }
    else
    {
        ESP_LOGI(TAG, "Credenciales WiFi ya disponibles, omitiendo provisioning");
        wifi_prov_mgr_deinit();

        ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
        if (has_stored_cfg)
        {
            ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &stored_cfg));
        }
        ESP_ERROR_CHECK(esp_wifi_start());

        if (!has_stored_cfg)
        {
            wifi_config_t current_cfg;
            if (esp_wifi_get_config(WIFI_IF_STA, &current_cfg) == ESP_OK)
            {
                save_wifi_credentials_to_nvs(&current_cfg.sta);
            }
        }
    }

    ESP_LOGI(TAG, "WiFi listo, continuando con la lógica de aplicación");

    // Inicialmente apagado
    gpio_set_level(ACTIVITY_PIN, SET_ON);

    tcp_socket_mutex = xSemaphoreCreateMutex();

    uart_init();
    vTaskDelay(5000 / portTICK_PERIOD_MS);

    xTaskCreate(tcp_server_task, "tcp_server", 4096, NULL, 5, NULL);
    xTaskCreate(uart_to_tcp_task, "uart_to_tcp", 4096, NULL, 5, NULL);
}
