FROM ghcr.io/jessegoodier/toolbox-homebrew:latest

COPY --chown=toolbox:toolbox . /home/toolbox/zsh-config-repo

WORKDIR /home/toolbox/zsh-config-repo
