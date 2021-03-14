FROM python:3.8-slim-buster as builder

RUN set -eux \
	&& apt update \
	&& apt install -y \
		bc \
		gcc

ARG VERSION=latest
RUN set -eux \
	&& if [ "${VERSION}" = "latest" ]; then \
		pip3 install --no-cache-dir --no-compile bandit; \
	else \
		pip3 install --no-cache-dir --no-compile "bandit>=${VERSION},<$(echo "${VERSION}+0.1" | bc)"; \
	fi \
	\
	&& bandit --version | grep -E '^bandit\s[0-9]+' \
	\
	&& pip3 install --no-cache-dir \
		lxml \
	\
	&& find /usr/lib/ -name '__pycache__' -print0 | xargs -0 -n1 rm -rf \
	&& find /usr/lib/ -name '*.pyc' -print0 | xargs -0 -n1 rm -rf

RUN set -eux && ls -lap /usr/lib
RUN set -eux && ls -lap /usr/local/lib

FROM alpine:3 as production
# https://github.com/opencontainers/image-spec/blob/master/annotations.md
#LABEL "org.opencontainers.image.created"=""
#LABEL "org.opencontainers.image.version"=""
#LABEL "org.opencontainers.image.revision"=""
LABEL "maintainer"="cytopia <cytopia@everythingcli.org>"
LABEL "org.opencontainers.image.authors"="cytopia <cytopia@everythingcli.org>"
LABEL "org.opencontainers.image.vendor"="cytopia"
LABEL "org.opencontainers.image.licenses"="MIT"
LABEL "org.opencontainers.image.url"="https://github.com/cytopia/docker-bandit"
LABEL "org.opencontainers.image.documentation"="https://github.com/cytopia/docker-bandit"
LABEL "org.opencontainers.image.source"="https://github.com/cytopia/docker-bandit"
LABEL "org.opencontainers.image.ref.name"="bandit ${VERSION}"
LABEL "org.opencontainers.image.title"="bandit ${VERSION}"
LABEL "org.opencontainers.image.description"="bandit ${VERSION}"

RUN set -eux \
	&& apk add --no-cache python3 \
	&& ln -sf /usr/bin/python3 /usr/bin/python \
	&& ln -sf /usr/bin/python3 /usr/local/bin/python \
	&& find /usr/lib/ -name '__pycache__' -print0 | xargs -0 -n1 rm -rf \
	&& find /usr/lib/ -name '*.pyc' -print0 | xargs -0 -n1 rm -rf
COPY --from=builder /usr/local/lib/python3.8/site-packages/ /usr/lib/python3.8/site-packages/
COPY --from=builder /usr/local/bin/bandit /usr/bin/bandit
WORKDIR /data
ENTRYPOINT ["bandit"]
