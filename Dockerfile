# syntax=docker/dockerfile:1
# NO_AUTO_UPDATE
FROM ghcr.io/jessegoodier/toolbox-homebrew:latest

COPY --chown=toolbox:toolbox . /home/toolbox/zsh-config-repo

WORKDIR /home/toolbox/zsh-config-repo
