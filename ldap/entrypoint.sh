#!/bin/bash
set -e

# --- Configurar de forma global la ruta de Keytab para SASL/GSSAPI ---
export KRB5_KTNAME="/etc/krb5.keytab"

DOMAIN=${DOMAIN:-fis.epn.ec}
BASE_DN=${LDAP_BASE_DN:-dc=fis,dc=epn,dc=ec}
ADMIN_PASS=${LDAP_ADMIN_PASSWORD:-changeme}
FIRST_RUN_FLAG="/var/lib/ldap/.configured"

if [ "$LDAP_ROLE" = "master" ]; then
    CERT_NAME="ldap1"
else
    CERT_NAME="ldap2"
fi

echo "=== Copiando certificados TLS ==="
mkdir -p /etc/ldap/certs
cp /certs/ldap/${CERT_NAME}.key /certs/ldap/${CERT_NAME}.crt /certs/ca/ca.crt /etc/ldap/certs/
chown openldap:openldap /etc/ldap/certs/*
chmod 640 /etc/ldap/certs/${CERT_NAME}.key
chmod 644 /etc/ldap/certs/${CERT_NAME}.crt /etc/ldap/certs/ca.crt

if ! grep -q "TLS_CACERT.*/etc/ldap/certs/ca.crt" /etc/ldap/ldap.conf 2>/dev/null; then
  echo "TLS_CACERT /etc/ldap/certs/ca.crt" >> /etc/ldap/ldap.conf
fi

# --- Configuración del Keytab de Kerberos ---
if [ "$LDAP_ROLE" = "master" ]; then
    echo "=== [Kerberos] Buscando Keytab compartido para LDAP ==="
    # Bucle de espera para asegurar que el KDC master ya haya escrito el archivo
    for i in $(seq 1 30); do
        if [ -f /shared-keytabs/ldap1.keytab ]; then
            echo "[Kerberos] Keytab ldap1.keytab encontrado."
            break
        fi
        echo "[Kerberos] Esperando keytab de LDAP... ($i/30)"
        sleep 2
    done

    if [ -f /shared-keytabs/ldap1.keytab ]; then
        cp /shared-keytabs/ldap1.keytab /etc/krb5.keytab
        chown openldap:openldap /etc/krb5.keytab
        chmod 640 /etc/krb5.keytab
        echo "[Kerberos] Keytab copiado y configurado con éxito en /etc/krb5.keytab"
    else
        echo "[Kerberos] ADVERTENCIA: No se encontró ldap1.keytab en /shared-keytabs tras el tiempo de espera"
    fi
fi

if [ ! -f "$FIRST_RUN_FLAG" ]; then
  echo "=== Primera ejecución: configurando slapd ==="

  debconf-set-selections << EOF
slapd slapd/internal/generated_adminpw password ${ADMIN_PASS}
slapd slapd/internal/adminpw password ${ADMIN_PASS}
slapd slapd/password2 password ${ADMIN_PASS}
slapd slapd/password1 password ${ADMIN_PASS}
slapd slapd/domain string ${DOMAIN}
slapd shared/organization string FIS-EPN
slapd slapd/backend string MDB
slapd slapd/purge_database boolean false
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
EOF

  dpkg-reconfigure -f noninteractive slapd

  cat > /tmp/tls.ldif << EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ldap/certs/${CERT_NAME}.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ldap/certs/${CERT_NAME}.key
-
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ldap/certs/ca.crt
EOF

  slapd -h "ldapi:/// ldap:///" -u openldap -g openldap &
  sleep 3

  ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/tls.ldif

  if [ "$LDAP_ROLE" = "master" ]; then
      echo "=== Cargando estructura base (OUs, grupo, usuarios) ==="
      for f in /datos/*.ldif; do
        echo "Cargando $f..."
        ldapadd -x -D "cn=admin,${BASE_DN}" -w "${ADMIN_PASS}" -f "$f" || echo "  (posible entrada ya existente, continuando)"
      done

      echo "=== Habilitando syncprov (para replicación) ==="
      cat > /tmp/syncprov_mod.ldif << EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF
      ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/syncprov_mod.ldif

      cat > /tmp/syncprov_overlay.ldif << EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpCheckpoint: 100 10
olcSpSessionLog: 100
EOF
      ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/syncprov_overlay.ldif

      cat > /tmp/syncprov_index.ldif << EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: entryCSN eq
-
add: olcDbIndex
olcDbIndex: entryUUID eq
EOF
      ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/syncprov_index.ldif
  fi

  echo "=== Deteniendo instancia temporal de slapd ==="
  pkill -TERM slapd 2>/dev/null || true

  for i in $(seq 1 10); do
    if ! pgrep slapd > /dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  pkill -KILL slapd 2>/dev/null || true
  sleep 1

  touch "$FIRST_RUN_FLAG"
else
  echo "=== Ya configurado previamente, iniciando directamente ==="
fi

echo "=== Iniciando slapd en primer plano ==="
exec slapd -d 1 -h "ldap:/// ldapi:/// ldaps:///" -u openldap -g openldap