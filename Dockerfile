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

# for the moment, edge has the latest version of pgpool
ARG ALPINE_VERSION=edge

FROM --platform=linux/amd64 golang:1.17-alpine as go_utils
RUN apk add --no-cache git make build-base python3 curl
WORKDIR /src

# building from source until a release includes https://github.com/influxdata/telegraf/pull/10097
RUN git clone https://github.com/influxdata/telegraf.git

# using our fork until/unless https://github.com/subfuzion/envtpl/pull/11 lands
RUN git clone https://github.com/odenio/envtpl

# using our fork until/unless https://github.com/pgpool/pgpool2_exporter/pull/11 lands
RUN git clone https://github.com/odenio/pgpool2_exporter.git

WORKDIR /src/telegraf
RUN git checkout 697855c98b38a81bbe7dead59355f5740875448a
RUN make all

WORKDIR /src/envtpl
RUN go install ./cmd/envtpl/...

WORKDIR /src/pgpool2_exporter
RUN git checkout 0b12a3c2dfdacadccabb24a5226a8531deff63ba
RUN go install ./pgpool2_exporter.go

FROM --platform=linux/amd64 alpine:${ALPINE_VERSION}
RUN apk add --no-cache curl python3

# we build this in the deploy container because there's no guarantee
# that golang:XXX-alpine and alpine:YYY will have the same python versions
RUN mkdir -p /usr/local/gcloud \
  && curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz | \
  tar -C /usr/local/gcloud -zxvf - \
  && /usr/local/gcloud/google-cloud-sdk/install.sh

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
COPY --from=go_utils /go/bin/pgpool2_exporter /bin/pgpool2_exporter
COPY --from=go_utils /src/telegraf/telegraf /bin/telegraf

RUN mkdir /etc/templates
COPY conf/*.conf /etc/templates/
COPY conf/*.tmpl /etc/templates/
COPY bin/*.sh /usr/bin/

EXPOSE 5432
EXPOSE 9898
EXPOSE 9719
EXPOSE 8089/udp
