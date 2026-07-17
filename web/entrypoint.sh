#!/bin/bash
set -e

# --- Configurar krb5.conf básico ---
cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = FIS.EPN.EC
    dns_lookup_realm = false
    dns_lookup_kdc = false

[realms]
    FIS.EPN.EC = {
        kdc = kdc1.fis.epn.ec
        admin_server = kdc1.fis.epn.ec
    }

[domain_realm]
    .fis.epn.ec = FIS.EPN.EC
    fis.epn.ec = FIS.EPN.EC
EOF

# --- Configurar Apache con SSL y Kerberos ---
cat > /etc/apache2/sites-available/default-ssl.conf <<EOF
<IfModule mod_ssl.c>
    <VirtualHost _default_:443>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html
        ServerName web.fis.epn.ec

        # Configuración TLS con tus certificados ECDSA
        SSLEngine on
        SSLCertificateFile    /etc/ssl/certs/web.crt
        SSLCertificateKeyFile /etc/ssl/private/web.key
        SSLCACertificateFile  /etc/ssl/certs/ca.crt

        # Proteger el directorio raíz con Kerberos (GSSAPI)
        <Directory /var/www/html>
            AuthType GSSAPI
            AuthName "Acceso Seguro FIS EPN - Kerberos"
            GssapiCredStore keytab:/etc/apache2/web.keytab
            Require valid-user
        </Directory>

        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>
</IfModule>
EOF

# Habilitar el sitio SSL en Apache
a2ensite default-ssl.conf

# --- Esperar y Configurar el Keytab de Servicio ---
echo "=== [Web] Buscando Keytab compartido para el servicio Web ==="
for i in $(seq 1 30); do
    if [ -f /shared-keytabs/web.keytab ]; then
        echo "[Web] Keytab web.keytab encontrado."
        break
    fi
    echo "[Web] Esperando keytab de Web... ($i/30)"
    sleep 2
done

if [ -f /shared-keytabs/web.keytab ]; then
    cp /shared-keytabs/web.keytab /etc/apache2/web.keytab
    chown www-data:www-data /etc/apache2/web.keytab
    chmod 600 /etc/apache2/web.keytab
    echo "[Web] Keytab de Apache configurado."
else
    echo "[Web] ADVERTENCIA: No se encontró web.keytab en /shared-keytabs"
fi

# --- Configurar Certificados SSL ---
# Copiar certificados desde el volumen compartido de tu CA
mkdir -p /etc/ssl/private
cp /certs/web/web.crt /etc/ssl/certs/web.crt 2>/dev/null || true
cp /certs/web/web.key /etc/ssl/private/web.key 2>/dev/null || true
cp /certs/ca/ca.crt /etc/ssl/certs/ca.crt 2>/dev/null || true

# --- Solución al error de DefaultRuntimeDir ---
# Asegurar que existan los directorios de ejecución y logs de Apache
mkdir -p /var/run/apache2 /var/lock/apache2 /var/log/apache2

# Cargar variables de entorno oficiales de Apache para Ubuntu
export APACHE_RUN_USER=www-data
export APACHE_RUN_GROUP=www-data
export APACHE_PID_FILE=/var/run/apache2/apache2.pid
export APACHE_RUN_DIR=/var/run/apache2
export APACHE_LOCK_DIR=/var/lock/apache2
export APACHE_LOG_DIR=/var/log/apache2

# Iniciar Apache en primer plano
echo "=== Iniciando Apache en primer plano ==="
exec apache2 -DFOREGROUND