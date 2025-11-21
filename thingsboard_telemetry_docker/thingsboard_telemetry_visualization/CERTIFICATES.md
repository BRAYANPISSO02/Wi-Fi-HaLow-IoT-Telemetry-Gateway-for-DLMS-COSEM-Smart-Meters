# 🔐 Certificados SSL/TLS - ThingsBoard Stack

**Fecha de generación:** 10 de noviembre de 2025  
**Ubicación:** `/home/pci/Documents/sebas_giraldo/Tesis-app/docker/thingsboard/certs/`  
**Estado:** ✅ **GENERADOS Y LISTOS PARA USO**  
**Tipo:** Certificados autofirmados (válidos para desarrollo)  
**Validez:** 3650 días (10 años) desde generación  
**Common Name (CN):** localhost

---

## 📂 Estructura de Certificados

```
certs/
├── ca/                                      # CA Raíz (Certificate Authority)
│   ├── ca.pem                              # Certificado CA (público)
│   └── ca_key.pem                          # Llave privada CA (PRIVADO - 600)
│
├── http/                                    # HTTPS (puerto 8080 → 443)
│   ├── server.pem                          # Certificado servidor web
│   └── server_key.pem                      # Llave privada (PRIVADO - 600)
│
├── mqtt/                                    # MQTTs (puerto 8883)
│   ├── mqttserver.pem                      # Certificado servidor MQTT
│   └── mqttserver_key.pem                  # Llave privada (PRIVADO - 600)
│
├── coap/                                    # CoAPs DTLS (puerto 5684)
│   ├── coapserver.pem                      # Certificado servidor CoAP
│   └── coapserver_key.pem                  # Llave privada (PRIVADO - 600)
│
└── lwm2m/                                   # LwM2M DTLS (puertos 5686, 5688)
    ├── lwm2mserver.pem                     # Certificado servidor LwM2M + Bootstrap
    ├── lwm2mserver_key.pem                 # Llave privada (PRIVADO - 600)
    └── lwm2mtruststorechain.pem            # Trust store para clientes IoT
```

**Permisos:**
- Certificados (*.pem): `644` (legible por todos)
- Llaves privadas (*_key.pem): `600` (solo propietario)

---

## 🚀 Estado Actual de SSL/TLS

### ⚠️ PROTOCOLOS DESHABILITADOS POR DEFECTO

Los certificados están **generados y montados** en el contenedor ThingsBoard, pero **SSL/TLS está DESHABILITADO** para facilitar desarrollo local sin cifrado.

**Variables en `docker-compose.yml`:**
```yaml
SSL_ENABLED: false                        # ← HTTPS deshabilitado
MQTT_SSL_ENABLED: false                   # ← MQTTs deshabilitado
COAP_DTLS_ENABLED: false                  # ← CoAPs deshabilitado
LWM2M_SERVER_CREDENTIALS_ENABLED: false   # ← LwM2M DTLS deshabilitado
LWM2M_BS_CREDENTIALS_ENABLED: false       # ← Bootstrap DTLS deshabilitado
```

### 🔓 Puertos Activos (sin cifrado)
- HTTP: 8080
- MQTT: 1883
- CoAP: 5683
- LwM2M Server: 5685
- LwM2M Bootstrap: 5687

### 🔒 Puertos SSL Disponibles (requieren habilitar)
- HTTPS: 8080 (o 443 si reconfiguras)
- MQTTs: 8883
- CoAPs: 5684
- LwM2M Server DTLS: 5686
- LwM2M Bootstrap DTLS: 5688 ⭐ **PRIORIDAD USUARIO**

---

## ✅ Cómo Habilitar SSL/TLS

### Paso 1: Editar `docker-compose.yml`

Cambia las siguientes variables de `false` a `true`:

```yaml
# Para HTTPS
SSL_ENABLED: true

# Para MQTT seguro
MQTT_SSL_ENABLED: true

# Para CoAP seguro
COAP_DTLS_ENABLED: true

# Para LwM2M Server seguro (puerto 5686)
LWM2M_SERVER_CREDENTIALS_ENABLED: true

# Para LwM2M Bootstrap seguro (puerto 5688) - CASO DE USO PRINCIPAL
LWM2M_BS_CREDENTIALS_ENABLED: true

# Para validar certificados de clientes IoT (opcional)
LWM2M_TRUST_CREDENTIALS_ENABLED: true
```

### Paso 2: Reiniciar el Stack

```bash
cd /home/pci/Documents/sebas_giraldo/Tesis-app/docker/thingsboard
./reset.sh --soft  # Detiene sin borrar datos
./up.sh            # Levanta con nueva configuración
```

### Paso 3: Verificar

```bash
# Ver logs de inicio SSL
docker compose logs thingsboard-ce | grep -i "ssl\|dtls\|tls"

# Probar conexión DTLS con openssl
openssl s_client -connect localhost:5686 -dtls1_2  # LwM2M Server
openssl s_client -connect localhost:5688 -dtls1_2  # LwM2M Bootstrap

# Probar MQTTs
mosquitto_sub -h localhost -p 8883 \
  --cafile certs/mqtt/mqttserver.pem \
  -t 'v1/devices/me/telemetry' \
  -u 'DEVICE_TOKEN'
```

---

## 🔍 Verificación de Certificados

### Ver detalles del certificado

```bash
# Certificado LwM2M (Bootstrap - prioridad usuario)
openssl x509 -in certs/lwm2m/lwm2mserver.pem -text -noout

# Verificar fechas de expiración
openssl x509 -in certs/lwm2m/lwm2mserver.pem -noout -dates

# Ver Subject y Common Name
openssl x509 -in certs/mqtt/mqttserver.pem -noout -subject -issuer
```

### Validar par certificado-llave

```bash
# Los módulos deben coincidir
openssl x509 -noout -modulus -in certs/lwm2m/lwm2mserver.pem | openssl md5
openssl rsa -noout -modulus -in certs/lwm2m/lwm2mserver_key.pem | openssl md5
```

---

## 🛠️ Regenerar Certificados

### Si los certificados expiran o necesitas cambiar el CN:

```bash
cd /home/pci/Documents/sebas_giraldo/Tesis-app/docker/thingsboard

# Eliminar certificados antiguos
rm -rf certs/

# Regenerar con localhost
./generate-certs.sh

# Regenerar con dominio personalizado
./generate-certs.sh mi-thingsboard.local

# Reiniciar stack
./reset.sh --soft && ./up.sh
```

---

## 🏭 Migración a Producción

⚠️ **CRÍTICO:** Los certificados actuales son **autofirmados** y **no son válidos para producción**.

### Para PRODUCCIÓN necesitas:

1. **Certificados de CA reconocida:**
   - Let's Encrypt (gratuito, automatizable)
   - DigiCert, Sectigo, GlobalSign (comerciales)
   - CA corporativa interna

2. **Reemplazar archivos en `certs/`:**
   ```bash
   # Ejemplo con Let's Encrypt (certbot)
   sudo certbot certonly --standalone -d tu-dominio.com
   
   # Copiar certificados
   cp /etc/letsencrypt/live/tu-dominio.com/fullchain.pem certs/lwm2m/lwm2mserver.pem
   cp /etc/letsencrypt/live/tu-dominio.com/privkey.pem certs/lwm2m/lwm2mserver_key.pem
   
   # Ajustar permisos
   chmod 644 certs/lwm2m/lwm2mserver.pem
   chmod 600 certs/lwm2m/lwm2mserver_key.pem
   ```

3. **Actualizar Common Name:**
   - El CN del certificado debe coincidir con el hostname/IP usado por los clientes
   - Para dispositivos IoT, usa IP pública o dominio DNS

4. **Renovación automática:**
   - Configura cronjob para renovar certificados Let's Encrypt cada 60 días
   - Script de reinicio del stack tras renovación

---

## 🐛 Troubleshooting SSL

### Error: "Certificate verification failed"

**Causa:** El Common Name no coincide con el hostname usado.

**Solución:**
```bash
# Verificar CN del certificado
openssl x509 -in certs/lwm2m/lwm2mserver.pem -noout -subject

# Regenerar con CN correcto
./generate-certs.sh 192.168.1.100  # O tu IP/dominio real
```

### Error: "DTLS handshake timeout"

**Causa:** Configuración de cipher suites incompatible.

**Solución:**
```yaml
# En docker-compose.yml, asegurar:
LWM2M_RECOMMENDED_CIPHERS: true
LWM2M_DTLS_RETRANSMISSION_TIMEOUT_MS: 9000
```

### Error: "Permission denied" al leer certificado

**Causa:** Permisos incorrectos en archivos de certificado.

**Solución:**
```bash
# Ajustar permisos
chmod 644 certs/*/*.pem
chmod 600 certs/*/*_key.pem
```

### Certificados autofirmados en cliente

Para desarrollo, deshabilita verificación SSL en el cliente:
```python
# Python ejemplo
import ssl
context = ssl.create_default_context()
context.check_hostname = False
context.verify_mode = ssl.CERT_NONE
```

**⚠️ NUNCA uses `verify_mode = CERT_NONE` en producción**

---

## 📋 Checklist para Agentes/Desarrolladores

- [x] Certificados generados en `certs/`
- [x] Permisos configurados (644 certs, 600 keys)
- [x] Volumen montado en docker-compose.yml: `./certs:/certs:ro`
- [ ] Variables `*_ENABLED` cambiadas a `true` (según necesidad)
- [ ] Stack reiniciado tras habilitar SSL
- [ ] Logs verificados para errores SSL/DTLS
- [ ] Conexión DTLS probada con openssl s_client
- [ ] Documentación de clientes IoT actualizada con nuevos puertos

---

## 📚 Referencias

- **ThingsBoard SSL Docs:** https://thingsboard.io/docs/user-guide/install/config/
- **LwM2M Transport Config:** https://thingsboard.io/docs/user-guide/install/lwm2m-transport-config/
- **OpenSSL Commands:** https://www.openssl.org/docs/man1.1.1/man1/
- **DTLS RFC 6347:** https://datatracker.ietf.org/doc/html/rfc6347
- **Let's Encrypt:** https://letsencrypt.org/getting-started/

---

## 🔄 Historial de Cambios

| Fecha | Acción | Responsable |
|-------|--------|-------------|
| 2025-11-10 | Generación inicial de certificados (localhost, 10 años) | GitHub Copilot Agent |
| 2025-11-10 | Configuración completa SSL en docker-compose.yml | GitHub Copilot Agent |
| 2025-11-10 | Documentación CERTIFICATES.md creada | GitHub Copilot Agent |

---

**Última actualización:** 10 de noviembre de 2025  
**Contacto:** Para renovar o cambiar certificados, ejecutar `./generate-certs.sh` o contactar al administrador del sistema.

---

## 🎯 Resumen Ejecutivo para Agentes

**CONTEXTO CRÍTICO:**
- ✅ Certificados SSL/TLS **YA GENERADOS** en `./certs/`
- ⚠️ SSL **DESHABILITADO** por defecto (flags en false)
- 🎯 **Objetivo usuario:** Habilitar LwM2M Bootstrap DTLS (puerto 5688)
- 🔧 **Acción requerida:** Cambiar `LWM2M_BS_CREDENTIALS_ENABLED: false` → `true`
- 📁 **Archivos críticos:** 
  - `docker-compose.yml` (configuración SSL)
  - `certs/lwm2m/lwm2mserver.pem` (certificado)
  - `certs/lwm2m/lwm2mserver_key.pem` (llave privada)
- 🔄 **Tras cambios:** `./reset.sh --soft && ./up.sh`

**NO REGENERAR CERTIFICADOS** a menos que:
- Estén expirados (verificar con `openssl x509 -in certs/*/server.pem -noout -dates`)
- Se requiera cambiar Common Name
- Se migren a certificados de CA en producción
