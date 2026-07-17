FROM ubuntu:24.04

ENV TZ=America/Guayaquil
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 1. Instalar utilidades para manejar repositorios y añadir "universe"
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    software-properties-common iproute2 procps tzdata && \
    add-apt-repository -y universe && \
    apt-get update

# 2. Instalar el KDC de Kerberos, el admin server y el demonio de propagación desde universe
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
    krb5-kdc krb5-admin-server krb5-kpropd krb5-user && \
    rm -rf /var/lib/apt/lists/*

COPY krb5.conf /etc/krb5.conf
COPY kdc.conf /etc/krb5kdc/kdc.conf
COPY kpropd.acl /etc/krb5kdc/kpropd.acl

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 88 749 754

ENTRYPOINT ["/entrypoint.sh"]