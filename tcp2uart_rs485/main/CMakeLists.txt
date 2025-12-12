idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES
        wifi_provisioning
        nvs_flash
        esp_netif
        esp_wifi
        lwip
        esp_event
        driver
        esp_timer
        esp_system
        esp_eth
        esp_http_server
)
