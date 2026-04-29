FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y openssh-server && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash rocky && \
    echo 'rocky:bluemoon' | chpasswd

RUN mkdir -p /run/sshd

COPY astrophage_data.txt /home/rocky/astrophage_data.txt
RUN chown rocky:rocky /home/rocky/astrophage_data.txt && \
    chmod 640 /home/rocky/astrophage_data.txt

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

CMD ["/entrypoint.sh"]
