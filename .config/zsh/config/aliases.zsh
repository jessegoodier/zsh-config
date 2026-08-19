alias bob='bobide'
alias bobcli='/opt/homebrew/bin/bob'
alias brewup='brew update && brew upgrade -y'
alias cursor='cursor --classic'
alias deit='docker exec -i -t'
alias df='df -h'
alias ds='git diff --staged'
alias fed="kgsec federated-store -oyaml|ksd"
alias fonts='fc-list : family | sort -u'
alias gccl='gcloud container clusters list 2>/dev/null'
alias grep='grep --color=auto'
alias gs='git status -s'
alias h='history'
alias hru='helm repo update'
# alias jq='jq -C'
alias kd='kubectl describe'
alias kdelsts="kubectl delete sts"
alias kdpi="kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}' | tr -s '[[:space:]]' '\n' | sort -u"
alias kests='kubectl edit sts'
alias kg='kubectl get'
alias kgep='kubectl get endpointslices'
alias kgnol='kubectl get nodes --show-labels'
alias kgsts="kubectl get sts"
alias krrsts='kubectl rollout restart sts'
alias md='mkdir -p'
alias ta='tmux attach'
alias tkill='tmux kill-server'
alias tks='tmux kill-session -t'
alias tl='tmux list-sessions'
alias tree='eza --tree --icons=auto'
alias whatsmyip='curl -s -X GET -4 https://ifconfig.co'
export BAT_PAGER='less -R'
export LESS='-R'
export PAGER=less
unalias hin 2>/dev/null
unalias hun 2>/dev/null
unalias hup 2>/dev/null
