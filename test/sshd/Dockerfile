# Throwaway SSH + rsync server that stands in for a hosting server during tests
FROM alpine:3.20
RUN apk add --no-cache openssh-server rsync bash \
 && ssh-keygen -A \
 && adduser -D -s /bin/bash deploy \
 && sed -i 's/^deploy:!/deploy:*/' /etc/shadow \
 && mkdir -p /home/deploy/.ssh /home/deploy/public/wp-content/themes \
 && chown -R deploy:deploy /home/deploy
CMD ["/usr/sbin/sshd", "-D", "-e"]
