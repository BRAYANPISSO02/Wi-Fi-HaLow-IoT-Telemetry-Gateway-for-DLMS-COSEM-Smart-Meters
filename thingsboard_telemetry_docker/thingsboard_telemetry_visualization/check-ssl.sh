#!/usr/bin/env bash
# Script de verificación SSL/TLS para ThingsBoard
# Uso: ./check-ssl.sh

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Verificación de Certificados SSL/TLS ===${NC}"
echo ""

# Verificar directorio de certificados
if [ -d "./certs" ]; then
    echo -e "${GREEN}✓ Directorio certs/ existe${NC}"
else
    echo -e "${RED}✗ Directorio certs/ NO encontrado${NC}"
    echo "  Ejecuta: ./generate-certs.sh"
    exit 1
fi

# Contar certificados
CERT_COUNT=$(find certs/ -name "*.pem" -type f | wc -l)
echo -e "${GREEN}✓ Certificados encontrados: $CERT_COUNT${NC}"

# Verificar certificados clave
echo ""
echo -e "${YELLOW}=== Certificados Principales ===${NC}"

for CERT in "certs/lwm2m/lwm2mserver.pem" "certs/mqtt/mqttserver.pem" "certs/http/server.pem"; do
    if [ -f "$CERT" ]; then
        echo -e "${GREEN}✓ $(basename $(dirname $CERT)): $(basename $CERT)${NC}"
        
        # Verificar fechas de expiración
        EXPIRY=$(openssl x509 -in "$CERT" -noout -enddate | cut -d= -f2)
        echo "  Expira: $EXPIRY"
        
        # Verificar CN
        CN=$(openssl x509 -in "$CERT" -noout -subject | grep -oP 'CN\s*=\s*\K[^,]+')
        echo "  Common Name: $CN"
        echo ""
    else
        echo -e "${RED}✗ $CERT NO encontrado${NC}"
    fi
done

# Verificar estado SSL en docker-compose.yml
echo -e "${YELLOW}=== Estado SSL en docker-compose.yml ===${NC}"

check_ssl_var() {
    local VAR=$1
    local LABEL=$2
    
    if grep -q "^[[:space:]]*${VAR}:[[:space:]]*true" docker-compose.yml 2>/dev/null; then
        echo -e "${GREEN}✓ $LABEL: HABILITADO${NC}"
    else
        echo -e "${YELLOW}⚠ $LABEL: DESHABILITADO${NC}"
    fi
}

check_ssl_var "SSL_ENABLED" "HTTPS"
check_ssl_var "MQTT_SSL_ENABLED" "MQTTs"
check_ssl_var "COAP_DTLS_ENABLED" "CoAPs"
check_ssl_var "LWM2M_SERVER_CREDENTIALS_ENABLED" "LwM2M Server DTLS"
check_ssl_var "LWM2M_BS_CREDENTIALS_ENABLED" "LwM2M Bootstrap DTLS"

echo ""
echo -e "${YELLOW}=== Documentación ===${NC}"
[ -f "CERTIFICATES.md" ] && echo -e "${GREEN}✓ CERTIFICATES.md (completa)${NC}" || echo -e "${RED}✗ CERTIFICATES.md NO encontrada${NC}"
[ -f ".certinfo" ] && echo -e "${GREEN}✓ .certinfo (resumen rápido)${NC}" || echo -e "${RED}✗ .certinfo NO encontrada${NC}"
[ -f ".ssl-status" ] && echo -e "${GREEN}✓ .ssl-status (estado)${NC}" || echo -e "${RED}✗ .ssl-status NO encontrada${NC}"

echo ""
echo -e "${GREEN}=== Verificación completa ===${NC}"
echo ""
echo "Para habilitar SSL/TLS:"
echo "  1. Editar docker-compose.yml"
echo "  2. Cambiar *_ENABLED: false → true"
echo "  3. ./reset.sh --soft && ./up.sh"
