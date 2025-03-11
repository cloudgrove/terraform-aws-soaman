FROM hashicorp/terraform:1.3.7 AS base
ARG DOCKER_PROJECT_DIR
ENV PROJECT_DIR=$DOCKER_PROJECT_DIR

FROM base AS builder
RUN apk add --update bash git findutils make openrc tree
WORKDIR $PROJECT_DIR
COPY . ./
RUN make test package
CMD tail -f /dev/null
