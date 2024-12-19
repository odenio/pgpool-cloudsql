# Copyright 2021 Oden Technologies Inc (https://oden.io/)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG ALPINE_VERSION=3.20
ARG GO_VERSION=1.23
ARG PLATFORM=linux/amd64
###
### Build PGPool-II from source in a build container
###
FROM --platform=${PLATFORM} alpine:${ALPINE_VERSION} AS pgpool_build
RUN apk update
RUN apk add build-base libpq-dev linux-headers openssl-dev>3
ENV pkgname=pgpool
ENV _pkgname=pgpool-II

ARG PGPOOL_VERSION=4.5.4
ENV PGPOOL_VERSION=${PGPOOL_VERSION}

ARG APPLY_PATCHES=false
ENV APPLY_PATCHES=${APPLY_PATCHES}

WORKDIR /usr/local/src

ADD https://www.pgpool.net/download.php?f=$_pkgname-$PGPOOL_VERSION.tar.gz pgpool.tgz

RUN tar zxf pgpool.tgz

WORKDIR /usr/local/src/$_pkgname-$PGPOOL_VERSION

ADD script script
ADD patches patches
RUN export APPLY_PATCHES
RUN ./script/apply-patches.sh

RUN ./configure \
		--prefix=/usr \
		--sysconfdir=/etc/$pkgname \
		--mandir=/usr/share/man \
		--infodir=/usr/share/info \
		--with-openssl \
		--disable-rpath

RUN make -j3
RUN strip src/pgpool
RUN make DESTDIR=/pgpool_bin install

###
### build envtpl
###
FROM --platform=${PLATFORM} golang:$GO_VERSION-alpine AS go_build
RUN apk update
RUN apk add --no-cache git make build-base python3 curl
WORKDIR /src

RUN git clone https://github.com/subfuzion/envtpl
ARG EXPORTER_VERSION=1.2.2
RUN git clone -b v${EXPORTER_VERSION} https://github.com/pgpool/pgpool2_exporter

WORKDIR /src/envtpl
# CVE-2024-45337
RUN go get golang.org/x/crypto
RUN go mod tidy
RUN go install -mod=mod ./cmd/envtpl/...

WORKDIR /src/pgpool2_exporter
RUN go install ./cmd/pgpool2_exporter/...

###
### put together everything in the deploy image
###
FROM --platform=${PLATFORM} alpine:${ALPINE_VERSION}
RUN apk update
RUN apk add --no-cache curl python3

ARG TELEGRAF_VERSION=1.26.2
RUN curl -sfL https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}_linux_amd64.tar.gz |\
  tar zxf - --strip-components=2 -C /

# we build this in the deploy container because there's no guarantee
# that golang:XXX-alpine and alpine:YYY will have the same python versions
RUN mkdir -p /usr/local/gcloud \
  && curl -sfL https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz | \
  tar -C /usr/local/gcloud -zxf - \
  && /usr/local/gcloud/google-cloud-sdk/install.sh -q

RUN apk add --no-cache \
      bash \
      coreutils \
      grep \
      jq \
      libevent \
      openssl \
      postgresql-client

# Adding the package path to local
ENV PATH=$PATH:/usr/local/gcloud/google-cloud-sdk/bin

COPY --from=go_build /go/bin/envtpl /bin/envtpl
COPY --from=go_build /go/bin/pgpool2_exporter /bin/pgpool2_exporter
COPY --from=pgpool_build /pgpool_bin/ /

RUN mkdir /etc/templates
COPY conf/*.conf /etc/templates/
COPY conf/*.tmpl /etc/templates/
COPY bin/*.sh /usr/bin/

EXPOSE 5432
EXPOSE 9898
EXPOSE 9090
EXPOSE 8089/udp
