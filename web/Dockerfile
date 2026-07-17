FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    apache2 \
    libapache2-mod-auth-gssapi \
    krb5-user \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN a2enmod ssl
RUN a2enmod auth_gssapi
RUN a2enmod headers

EXPOSE 80
EXPOSE 443

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]