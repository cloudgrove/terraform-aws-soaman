FROM hashicorp/terraform:1.3.7 AS base
ARG DOCKER_PROJECT_DIR
ARG TFC_TOKEN
ARG SET_TF_WORKSPACE
ENV PROJECT_DIR=$DOCKER_PROJECT_DIR
ENV TFC_TOKEN=$TFC_TOKEN
ENV SET_TF_WORKSPACE=$SET_TF_WORKSPACE

FROM base AS builder
RUN apk add --update bash git findutils make openrc tree
WORKDIR $PROJECT_DIR
COPY . ./
RUN make test package
CMD tail -f /dev/null
