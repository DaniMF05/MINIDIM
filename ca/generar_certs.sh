#!/bin/bash
# Archivo: ca/generar_certs.sh

# Detener el script si ocurre algún error
set -e

# Verificar si la CA ya existe para no sobreescribir los certificados
if [ -f "/certs/ca/ca.crt" ]; then
    echo "Los certificados ya existen en la carpeta ./certs. Omitiendo la generación para no romper la confianza."
    exit 0
fi

echo "Iniciando la generación de certificados ECDSA..."

# 1. Crear la estructura de directorios
mkdir -p /certs/ca /certs/ldap /certs/kerberos /certs/web

# 2. Generar la CA Raíz
echo "Generando CA Raíz..."
openssl req -x509 -nodes -days 3650 \
  -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout /certs/ca/ca.key \
  -out /certs/ca/ca.crt \
  -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS-EPN/CN=FIS Root CA"

# 3. Generar certificados para LDAP Master (ldap1)
echo "Generando certificados para LDAP Master (ldap1)..."
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout /certs/ldap/ldap1.key \
  -out /certs/ldap/ldap1.csr \
  -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS-EPN/CN=ldap1.fis.epn.ec"

openssl x509 -req -in /certs/ldap/ldap1.csr \
  -CA /certs/ca/ca.crt -CAkey /certs/ca/ca.key -CAcreateserial \
  -out /certs/ldap/ldap1.crt -days 365 -sha256 \
  -extfile <(printf "subjectAltName=DNS:ldap1.fis.epn.ec,DNS:ldap1")

# 4. Generar certificados para LDAP Réplica (ldap2)
echo "Generando certificados para LDAP Réplica (ldap2)..."
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout /certs/ldap/ldap2.key \
  -out /certs/ldap/ldap2.csr \
  -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS-EPN/CN=ldap2.fis.epn.ec"

openssl x509 -req -in /certs/ldap/ldap2.csr \
  -CA /certs/ca/ca.crt -CAkey /certs/ca/ca.key -CAcreateserial \
  -out /certs/ldap/ldap2.crt -days 365 -sha256 \
  -extfile <(printf "subjectAltName=DNS:ldap2.fis.epn.ec,DNS:ldap2")

# 5. Generar certificados para KDC Kerberos
echo "Generando certificados para Kerberos..."
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout /certs/kerberos/kdc.key \
  -out /certs/kerberos/kdc.csr \
  -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS-EPN/CN=kdc.fis.epn.ec"

openssl x509 -req -in /certs/kerberos/kdc.csr \
  -CA /certs/ca/ca.crt -CAkey /certs/ca/ca.key -CAcreateserial \
  -out /certs/kerberos/kdc.crt -days 365 -sha256 \
  -extfile <(printf "subjectAltName=DNS:kdc.fis.epn.ec,DNS:kdc")

# 6. Generar certificados para el Servicio Web (Flask, Go, etc.)
echo "Generando certificados para Web Server..."
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout /certs/web/web.key \
  -out /certs/web/web.csr \
  -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS-EPN/CN=web.fis.epn.ec"

openssl x509 -req -in /certs/web/web.csr \
  -CA /certs/ca/ca.crt -CAkey /certs/ca/ca.key -CAcreateserial \
  -out /certs/web/web.crt -days 365 -sha256 \
  -extfile <(printf "subjectAltName=DNS:web.fis.epn.ec,DNS:web")

# 7. Ajustar permisos para evitar problemas de lectura en Docker
echo "Ajustando permisos de seguridad..."
chmod -R 644 /certs/*/*.crt /certs/*/*.csr
chmod -R 600 /certs/*/*.key

echo "¡Todos los certificados ECDSA han sido generados exitosamente!"