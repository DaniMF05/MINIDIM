#!/bin/bash
set -e

REALM=${KRB5_REALM:-FIS.EPN.EC}
KADMIN_PASS=${KADMIN_PASSWORD:-adminpas}
ROLE=${KDC_ROLE:-master}
FIRST_RUN_FLAG="/var/lib/krb5kdc/.configured"

mkdir -p /var/lib/krb5kdc /etc/krb5kdc

# --- CONFIGURACIÓN PARA EL MAESTRO ---
if [ "$ROLE" = "master" ]; then
    echo "=== [Master] Configurando ACLs de Administración ==="
    echo "*/admin@${REALM} *" > /etc/krb5kdc/kadm5.acl

    if [ ! -f "$FIRST_RUN_FLAG" ]; then
        echo "=== [Master] Inicializando base de datos KDC ==="
        kdb5_util create -s -r "${REALM}" -P "${KADMIN_PASS}"

        echo "=== [Master] Creando Principals de Administración y Usuarios ==="
        kadmin.local -q "addprinc -pw ${KADMIN_PASS} admin/admin@${REALM}"
        kadmin.local -q "addprinc -pw emaflapas emafla@${REALM}"
        kadmin.local -q "addprinc -pw jruedapas jrueda@${REALM}"
        kadmin.local -q "addprinc -pw scollahuazopas scollahuazo@${REALM}"

        echo "=== [Master] Creando Principals de Host ==="
        kadmin.local -q "addprinc -randkey host/kdc1.fis.epn.ec@${REALM}"
        kadmin.local -q "addprinc -randkey host/kdc2.fis.epn.ec@${REALM}"
        
        # Principal de servicio para LDAP
        kadmin.local -q "addprinc -randkey ldap/ldap1.fis.epn.ec@${REALM}"

        echo "=== [Master] Exportando Keytab para LDAP ==="
        mkdir -p /shared-keytabs
        kadmin.local -q "ktadd -k /shared-keytabs/ldap1.keytab ldap/ldap1.fis.epn.ec@${REALM}"
        chmod 644 /shared-keytabs/ldap1.keytab

        echo "=== [Master] Exportando Keytab de Host para kdc2 ==="
        # Aquí escribimos el keytab de kdc2 en el volumen compartido, tal como lo espera la réplica
        kadmin.local -q "ktadd -k /shared-keytabs/kdc2.keytab host/kdc2.fis.epn.ec@${REALM}"
        chmod 644 /shared-keytabs/kdc2.keytab

        # El maestro también necesita su propio keytab para validar la identidad al propagar
        kadmin.local -q "ktadd -k /etc/krb5.keytab host/kdc1.fis.epn.ec@${REALM}"
        # Agregar esto dentro de las inicializaciones del KDC master en su respectivo script:
        kadmin.local -q "addprinc -randkey HTTP/web.fis.epn.ec"
        kadmin.local -q "ktadd -k /shared-keytabs/web.keytab HTTP/web.fis.epn.ec"
        
        touch "$FIRST_RUN_FLAG"
        echo "=== [Master] Configuración completada con éxito ==="
    else
        echo "=== [Master] KDC ya configurado previamente ==="
    fi

    echo "=== [Master] Iniciando KDC y kadmind ==="
    kadmind -nofork &
    exec krb5kdc -n

# --- CONFIGURACIÓN PARA LA RÉPLICA ---
else
    echo "=== [Replica] Esperando keytab de host generado por el maestro ==="
    for i in $(seq 1 30); do
        if [ -f /shared-keytabs/kdc2.keytab ]; then
            echo "[Replica] Keytab de kdc2 encontrado."
            break
        fi
        echo "[Replica] Esperando keytab de kdc2... ($i/30)"
        sleep 2
    done
    cp /shared-keytabs/kdc2.keytab /etc/krb5.keytab

    if [ ! -f "$FIRST_RUN_FLAG" ]; then
        echo "=== [Replica] Primera ejecución: creando base de datos vacía ==="
        # Usamos la misma clave del master para que el archivo stash sea idéntico
        kdb5_util create -s -r "${REALM}" -P "${KADMIN_PASS}"
        touch "$FIRST_RUN_FLAG"
        echo "=== [Replica] Configuración inicial completa ==="
    else
        echo "=== [Replica] Ya configurado previamente ==="
    fi

    echo "=== [Replica] Iniciando krb5kdc ==="
    krb5kdc &

    echo "=== [Replica] Iniciando kpropd para escuchar actualizaciones ==="
    exec kpropd -S -a /etc/krb5kdc/kpropd.acl -d
fi