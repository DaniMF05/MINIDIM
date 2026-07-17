FROM ubuntu:24.04

# Evitar prompts interactivos durante la instalación
ENV DEBIAN_FRONTEND=noninteractive

# Instalar Apache, SSL, Kerberos Client, curl y el módulo GSSAPI
RUN apt-get update && apt-get install -y \
    apache2 \
    libapache2-mod-auth-gssapi \
    krb5-user \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Habilitar módulos necesarios en Apache
RUN a2enmod ssl
RUN a2enmod auth_gssapi
RUN a2enmod headers

# Exponer puertos estándar
EXPOSE 80
EXPOSE 443

# Copiar el script de inicio
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]