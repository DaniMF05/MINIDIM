# Proyecto bimestral de Computación Distribuida - MiniIDM

- Proyecto realizado por Joshua Daniel Menendez Farias
- Entregado el 17 de julio de 2026

Este proyecto implementa una infraestructura completa y orquestada de Gestión de Identidades (IdM) utilizando contenedores Docker. Garantiza tolerancia a fallos mediante la replicación de directorios, redundancia en autenticación y balanceo de carga.

## Arquitectura y Lógica del Sistema

El entorno está compuesto por cinco bloques principales que interactúan entre sí en una red privada virtual de Docker (`red-fis`):

1. **Directorio Central (OpenLDAP):**
   * **ldap1 (Maestro):** Base de datos principal de usuarios.
   * **ldap2 (Réplica):** Copia exacta de solo lectura sincronizada en tiempo real mediante el módulo *SyncProv*.
2. **Autenticación (Kerberos):**
   * **kdc1 (Primario):** Centro de distribución de claves encargado de emitir los tickets (TGT).
   * **kdc2 (Secundario):** Servidor de respaldo que recibe la base de datos de credenciales a través del servicio kprop. Entra en acción automáticamente si el primario cae.
3. **Balanceador de Carga (HAProxy):**
   * Punto de entrada único (balanceador.fis.epn.ec). Enruta las peticiones LDAP hacia ldap1 y redirige el tráfico hacia ldap2 en caso de detectar un fallo (*health-check*).
4. **Servicio Web Seguro (Apache):**
   * Servidor web (web.fis.epn.ec) protegido mediante certificados SSL/TLS y delegación de tickets Kerberos (SPNEGO/Negotiate). Solo permite el acceso si el usuario cuenta con un ticket válido emitido por los KDCs.
5. **Monitoreo de Infraestructura:**
   * **Prometheus & Grafana:** Recolectan y visualizan métricas de hardware (node-exporter) en tiempo real para medir el impacto y la recuperación durante escenarios de caída de servicios.

## Requisitos Previos

* Docker y Docker Compose (V2)
* make instalado en el sistema anfitrión.
* Permisos de superusuario (sudo) para limpiar los volúmenes de datos mapeados.

## Despliegue del Entorno

Todo el ciclo de vida de la infraestructura (limpieza, compilación de imágenes, inicialización de replicación y pruebas de conectividad) está automatizado en el archivo Makefile.

Para levantar el entorno completo, ejecuta:

```bash
make deploy
```

- Hay ciertos casos en los que el servidor ldap1 no se inicia correctamente, esto por la condicion de carrera que se llega a general al momento de levantar los contenedores. Se soluciona ejecutando nuevamente el comando `make deploy` hasta que todos los contenedores estén alzados.

## Comandos de Verificación Manual (Sanity Checks)

Los siguientes comandos son para comprobar de forma individual que cada servicio funciona correctamente:

### 1. Comprobar que funciona LDAP (Replicación y Balanceo)

Para verificar que las consultas LDAP responden y que la base de datos se distribuye correctamente, se realiza una búsqueda de usuario apuntando al balanceador o directamente al nodo réplica:

-  **Consulta a través del Balanceador:**

```bash
docker exec -it ldap1.fis.epn.ec ldapsearch -x -H ldap://balanceador.fis.epn.ec:389 -b "dc=fis,dc=epn,dc=ec" "(uid=*)"

```


- **Consulta directa al nodo Réplica (ldap2):**
```bash
docker exec -it ldap1.fis.epn.ec ldapsearch -x -H ldap://ldap2.fis.epn.ec:389 -b "dc=fis,dc=epn,dc=ec" "(uid=*)"

```



### 2. Comprobar que funciona Kerberos

Se puede listar de forma remota los principales (usuarios y servicios) registrados en el KDC para verificar que la base de datos criptográfica está activa tanto en el servidor primario como en el secundario:

* **Listar en KDC Primario (`kdc1`):**
```bash
docker exec -it kdc1.fis.epn.ec kadmin.local -q "list_principals"

```


* **Listar en KDC Secundario (`kdc2`):**
```bash
docker exec -it kdc2.fis.epn.ec kadmin.local -q "list_principals"

```



### 3. Comprobar que funciona el Servidor Web (Autenticación Protegida)

El servidor Apache exige obligatoriamente un ticket Kerberos para permitir el acceso. Puedes simular el flujo completo de un usuario dentro de la red utilizando el contenedor `web`:

1. **Petición sin credenciales (Acceso Denegado esperado):**
```bash
docker exec -it web.fis.epn.ec curl -I -k --negotiate -u : [https://web.fis.epn.ec](https://web.fis.epn.ec)

```
Debe responder un estado `HTTP/1.1 401 Unauthorized` ya que no posees un ticket activo.

2. **Iniciar sesión para obtener un ticket válido (TGT):**
```bash
docker exec -it web.fis.epn.ec kinit emafla@FIS.EPN.EC

```


(Ingresa la contraseña correspondiente al usuario).
3. **Petición con credenciales válidas (Acceso Exitoso):**
```bash
docker exec -it web.fis.epn.ec curl -k --negotiate -u : [https://web.fis.epn.ec](https://web.fis.epn.ec)

```


Ahora el servidor web validará el ticket mediante SPNEGO y te permitirá visualizar el contenido html protegido de la intranet de forma exitosa.

---

## Monitoreo (Dashboard)

Una vez levantado el sistema, el panel de métricas en tiempo real está disponible en:

* **URL:** `http://localhost:3000`
* **Credenciales:** `admin` / `admin`
