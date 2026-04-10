FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y vsftpd && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash stratt && \
    echo 'stratt:petrova' | chpasswd && \
    mkdir -p /var/run/vsftpd/empty

COPY shadow /home/stratt/shadow
RUN chown stratt:stratt /home/stratt/shadow && chmod 644 /home/stratt/shadow

COPY vsftpd.conf /etc/vsftpd.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 21

CMD ["/entrypoint.sh"]
