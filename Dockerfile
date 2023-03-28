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

# for the moment, 3.15 has the latest version of pgpool that we support
ARG ALPINE_VERSION=3.15

FROM --platform=linux/amd64 golang:1.17-alpine as go_utils
RUN apk add --no-cache git make build-base python3 curl
WORKDIR /src

RUN git clone https://github.com/subfuzion/envtpl

WORKDIR /src/envtpl
RUN go install ./cmd/envtpl/...

FROM --platform=linux/amd64 alpine:${ALPINE_VERSION}
RUN apk add --no-cache curl python3

ARG TELEGRAF_VERSION=1.24.2
RUN curl -sfL https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}_static_linux_amd64.tar.gz |\
  tar zxf - --strip-components=2 -C /

ARG EXPORTER_VERSION=1.2.0
RUN curl -sfL https://github.com/pgpool/pgpool2_exporter/releases/download/v${EXPORTER_VERSION}/pgpool2_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz |\
  tar zxf - --strip-components=1 -C /usr/bin

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
      pgpool \
      postgresql-client

# Adding the package path to local
ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin

COPY --from=go_utils /go/bin/envtpl /bin/envtpl

RUN mkdir /etc/templates
COPY conf/*.conf /etc/templates/
COPY conf/*.tmpl /etc/templates/
COPY bin/*.sh /usr/bin/

EXPOSE 5432
EXPOSE 9898
EXPOSE 9719
EXPOSE 8089/udp
