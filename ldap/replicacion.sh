docker exec -i ldap2.fis.epn.ec ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: adminpas
EOF

docker exec -i -e LDAPTLS_REQCERT=allow ldap2.fis.epn.ec ldapmodify -x \
	  -H ldaps://ldap2.fis.epn.ec:636 \
	  -D "cn=admin,cn=config" \
	  -w adminpas < ./ldap/datos/02-replica-syncrepl.ldif