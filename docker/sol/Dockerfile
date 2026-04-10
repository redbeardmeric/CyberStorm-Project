FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y openssh-server && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash ryland && \
    echo 'ryland:microbiology' | chpasswd

RUN mkdir -p /var/mail /run/sshd

COPY mail_ryland.txt /var/mail/ryland
RUN chown ryland:ryland /var/mail/ryland && chmod 640 /var/mail/ryland

COPY sshd_config /etc/ssh/sshd_config

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
