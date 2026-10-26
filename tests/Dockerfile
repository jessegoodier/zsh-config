# syntax=docker/dockerfile:1
FROM golang:1.27.3-alpine AS build-env

# NO_AUTO_UPDATE
FROM 1.31.8-alpine3.24 as runtime-env

FROM ghcr.io/jessegoodier/toolbox-homebrew:latest AS toolbox-env

COPY --chown=toolbox:toolbox . /home/toolbox/zsh-config-repo

WORKDIR /home/toolbox/zsh-config-repo
