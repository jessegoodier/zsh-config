# syntax=docker/dockerfile:1

FROM ghcr.io/jessegoodier/toolbox-homebrew:latest # NO_AUTO_UPDATE

COPY --chown=toolbox:toolbox . /home/toolbox/zsh-config-repo

WORKDIR /home/toolbox/zsh-config-repo
