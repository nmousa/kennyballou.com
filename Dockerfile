# DOCKER-VERSION 1.7.0

FROM alpine:3.3
MAINTAINER kballou@devnulllabs.io

RUN apk update && apk add \
    nginx

ADD ./nginx.conf /etc/nginx/nginx.conf

VOLUME ["/etc/nginx/ssl", "/etc/nginx/sites", "/srv/www", "/var/log/nginx"]

WORKDIR /etc/nginx

EXPOSE 80
EXPOSE 443

CMD ["nginx"]
