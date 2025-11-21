#!/usr/bin/env bash
set -e

# Script para generar certificados SSL/TLS autofirmados para ThingsBoard
# Para uso en DESARROLLO. En PRODUCCIÓN usa certificados firmados por una CA reconocida.

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Generador de Certificados SSL/TLS para ThingsBoard ===${NC}"
echo ""

# Directorio base para certificados
CERTS_DIR="./certs"
VALIDITY_DAYS=3650  # 10 años

# Información del certificado
COUNTRY="CO"
STATE="Antioquia"
CITY="Medellin"
ORG="ThingsBoard IoT"
OU="Development"
COMMON_NAME="${1:-localhost}"  # Usar primer argumento o localhost por defecto

echo -e "${GREEN}Configuración:${NC}"
echo "  - Directorio: $CERTS_DIR"
echo "  - Validez: $VALIDITY_DAYS días"
echo "  - Common Name: $COMMON_NAME"
echo ""

# Función para generar certificado y llave privada
generate_cert() {
    local NAME=$1
    local DIR=$2
    local CN=$3
    
    echo -e "${GREEN}Generando certificado para $NAME...${NC}"
    
    mkdir -p "$DIR"
    
    # Generar llave privada
    openssl genrsa -out "$DIR/${NAME}_key.pem" 2048 2>/dev/null
    
    # Generar certificado autofirmado
    openssl req -new -x509 \
        -key "$DIR/${NAME}_key.pem" \
        -out "$DIR/${NAME}.pem" \
        -days "$VALIDITY_DAYS" \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=$CN" \
        2>/dev/null
    
    # Permisos
    chmod 644 "$DIR/${NAME}.pem"
    chmod 600 "$DIR/${NAME}_key.pem"
    
    echo -e "  ✓ Certificado: $DIR/${NAME}.pem"
    echo -e "  ✓ Llave privada: $DIR/${NAME}_key.pem"
    echo ""
}

# Crear CA raíz (para trust store)
echo -e "${GREEN}=== 1. Creando CA raíz ===${NC}"
mkdir -p "$CERTS_DIR/ca"
openssl genrsa -out "$CERTS_DIR/ca/ca_key.pem" 4096 2>/dev/null
openssl req -new -x509 \
    -key "$CERTS_DIR/ca/ca_key.pem" \
    -out "$CERTS_DIR/ca/ca.pem" \
    -days "$VALIDITY_DAYS" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=ThingsBoard CA" \
    2>/dev/null
chmod 644 "$CERTS_DIR/ca/ca.pem"
chmod 600 "$CERTS_DIR/ca/ca_key.pem"
echo -e "  ✓ CA certificado: $CERTS_DIR/ca/ca.pem"
echo ""

# HTTP/HTTPS
echo -e "${GREEN}=== 2. Generando certificados HTTP/HTTPS ===${NC}"
generate_cert "server" "$CERTS_DIR/http" "$COMMON_NAME"

# MQTT/MQTTS
echo -e "${GREEN}=== 3. Generando certificados MQTT/MQTTS ===${NC}"
generate_cert "mqttserver" "$CERTS_DIR/mqtt" "$COMMON_NAME"

# CoAP/CoAPs
echo -e "${GREEN}=== 4. Generando certificados CoAP/CoAPs ===${NC}"
generate_cert "coapserver" "$CERTS_DIR/coap" "$COMMON_NAME"

# LwM2M Server y Bootstrap
echo -e "${GREEN}=== 5. Generando certificados LwM2M ===${NC}"
generate_cert "lwm2mserver" "$CERTS_DIR/lwm2m" "$COMMON_NAME"

# Trust store (CA chain para validar clientes)
echo -e "${GREEN}=== 6. Creando trust store ===${NC}"
cp "$CERTS_DIR/ca/ca.pem" "$CERTS_DIR/lwm2m/lwm2mtruststorechain.pem"
echo -e "  ✓ Trust store: $CERTS_DIR/lwm2m/lwm2mtruststorechain.pem"
echo ""

# Resumen
echo -e "${GREEN}=== ✓ Certificados generados exitosamente ===${NC}"
echo ""
echo -e "${YELLOW}IMPORTANTE - Próximos pasos:${NC}"
echo "1. Edita docker-compose.yml y cambia los flags *_ENABLED a 'true' para habilitar SSL"
echo "   Ejemplo: SSL_ENABLED: true, MQTT_SSL_ENABLED: true, LWM2M_SERVER_CREDENTIALS_ENABLED: true"
echo ""
echo "2. Si descomenta las contraseñas (*_KEY_PASSWORD), genera llaves con contraseña:"
echo "   openssl genrsa -aes256 -out server_key.pem 2048"
echo ""
echo "3. Para PRODUCCIÓN, reemplaza estos certificados autofirmados con certificados"
echo "   firmados por una CA reconocida (Let's Encrypt, DigiCert, etc.)"
echo ""
echo "4. Verifica los certificados con:"
echo "   openssl x509 -in $CERTS_DIR/mqtt/mqttserver.pem -text -noout"
echo ""
echo -e "${YELLOW}=== Estructura de directorios ===${NC}"
tree "$CERTS_DIR" 2>/dev/null || find "$CERTS_DIR" -type f
echo ""
