# Makefile - Proyecto MiniIdM

.PHONY: up setup-replica setup-kerberos-ha test-master test-replica test-kdc test-web deploy

# 1. Levantar la infraestructura base limpia
up:
	docker compose down -v
	sudo rm -rf ./ldap/data ./ldap/config ./kerberos/data-master ./kerberos/data-replica ./certs/*
	docker compose up -d --build
	@echo "Esperando 12 segundos a que LDAP y Kerberos arranquen e inicialicen..."
	sleep 12

# 2. Configurar la replicación en el nodo réplica de forma automática
setup-replica:
	chmod +x ./ldap/replicacion.sh
	./ldap/replicacion.sh

# 3. Propagar la base de datos de Kerberos al KDC Secundario (HA)
setup-kerberos-ha:
	@echo "=== [HA] Realizando volcado de base de datos en kdc1 ==="
	docker exec -i kdc1.fis.epn.ec kdb5_util dump /var/lib/krb5kdc/slave_datatrans
	@echo "=== [HA] Propagando base de datos a kdc2 mediante kprop ==="
	docker exec -i kdc1.fis.epn.ec kprop -f /var/lib/krb5kdc/slave_datatrans kdc2.fis.epn.ec

# 4. Bloque de Pruebas Automatizadas
test-master:
	@echo "=== [TEST] Verificando conexión a LDAP Master (Puerto 389) desde Web ==="
	docker exec -i web.fis.epn.ec bash -c "timeout 2 bash -c '</dev/tcp/ldap1.fis.epn.ec/389' && echo 'Conexión exitosa a LDAP Master'"
	sleep 2
	
test-replica:
	@echo "=== [TEST] Verificando conexión a LDAP Replica (Puerto 389) desde Web ==="
	docker exec -i web.fis.epn.ec bash -c "timeout 2 bash -c '</dev/tcp/ldap2.fis.epn.ec/389' && echo 'Conexión exitosa a LDAP Replica'"
	sleep 2

test-kdc:
	@echo "=== [TEST] Verificando disponibilidad de bases KDC (Primario y Secundario) ==="
	docker exec -i kdc1.fis.epn.ec kadmin.local -q "list_principals" | grep "K/M"
	docker exec -i kdc2.fis.epn.ec kadmin.local -q "list_principals" | grep "K/M"
	sleep 2
	
test-web:
	@echo "=== [TEST] Verificando acceso HTTP/Kerberos desde el contenedor Web ==="
	@echo "Nota: Se espera un error 401 Unauthorized por falta de ticket TGT interactivo."
	docker exec -i web.fis.epn.ec curl -I -k --negotiate -u : https://web.fis.epn.ec

# 5. Despliegue completo automatizado
deploy: up setup-replica setup-kerberos-ha test-master test-replica test-kdc test-web