# Archivo: ca/Dockerfile
FROM alpine:latest

# Instalar bash y openssl
RUN apk add --no-cache bash openssl

# Copiar el script de generación al contenedor
COPY generar_certs.sh /generar_certs.sh

# Dar permisos de ejecución
RUN chmod +x /generar_certs.sh

# El directorio de trabajo donde se montará el volumen de los certificados
WORKDIR /certs

# Definir el script como punto de entrada
ENTRYPOINT ["/generar_certs.sh"]