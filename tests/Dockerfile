# syntax=docker/dockerfile:1
FROM golang:1.27.3-alpine@sha256:d200d2dd76b03a99b52651fd1325aff7dcd35422c35c01bac56571b0507f3deb AS build-env

# NO_AUTO_UPDATE
FROM 1.31.8-alpine3.24 as runtime-env

FROM ghcr.io/jessegoodier/toolbox-homebrew:latest AS toolbox-env

COPY --chown=toolbox:toolbox . /home/toolbox/zsh-config-repo

WORKDIR /home/toolbox/zsh-config-repo
