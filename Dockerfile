# DOCKER-VERSION 1.7.0

FROM base/archlinux

RUN pacman-key --init; pacman-key --populate archlinux; pacman-key --refresh-keys
RUN pacman -Syu --noprogressbar --noconfirm nginx

ADD ./nginx.conf /etc/nginx/nginx.conf

VOLUME ["/etc/nginx/ssl", "/etc/nginx/sites", "/srv/www", "/var/log/nginx"]

WORKDIR /etc/nginx

EXPOSE 80
EXPOSE 443

CMD ["nginx"]
