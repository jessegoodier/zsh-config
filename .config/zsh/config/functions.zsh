# Colors
autoload -Uz colors && colors

C_RED=${fg[red]}
C_GREEN=${fg[green]}
C_YELLOW=${fg[yellow]}
C_CYAN=${fg[cyan]}
C_NC=${reset_color}

# SSH Agent / Keychain
_ssh_agent_lazy() {
	if [[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" ]] &&
		ssh-add -l >/dev/null 2>&1; then
		echo "${C_GREEN}SSH agent already active${C_NC}"
		return 0
	fi

	[[ -f ~/.keychain/"$HOST"-sh ]] && source ~/.keychain/"$HOST"-sh
	eval "$(keychain --eval --quiet --nogui --timeout 480 ~/.ssh/id_ed25519)" &&
	echo "${C_GREEN}SSH agent started${C_NC}"
}

# zoxide integration
z() {
	unset -f z
	eval "$(zoxide init zsh)"
	z "$@"
}

# open yazi either at the given directory
# or at the one zoxide suggests
y() {
	if [[ -n $1 ]]; then
		if [ -d "$1" ]; then
			yazi "$1"
		else
			yazi "$(zoxide query "$1")"
		fi
	else
		yazi
	fi
}

# fnm lazy load
_fnm_lazy_load() {
	if [[ -f package.json ]]; then
		eval "$(fnm env)" 2>/dev/null || return
		add-zsh-hook -d chpwd _fnm_lazy_load
	fi
}
_fnm_lazy_load
add-zsh-hook -d chpwd _fnm_lazy_load 2>/dev/null
add-zsh-hook chpwd _fnm_lazy_load

# fnm manual activation
fnm-on() {
	eval "$(fnm env)" 2>/dev/null
	echo "${C_GREEN}Node activated${C_NC}"
}

# Extract one or more archive files based on their extension
extract() {
	if [[ "$1" == "help" || "$1" == "-h" || -z "$1" ]]; then
		echo "${C_CYAN}📦 extract${C_NC}: Universal archive extractor (supports multiple files)."
		echo "Usage: ${C_YELLOW}extract <archive> [archive...]${C_NC}"
		return 0
	fi

	for file in "$@"; do
		if [ -f "$file" ] ; then
			echo "${C_CYAN}Extracting '$file'...${C_NC}"
			case "$file" in
				*.tar.bz2)   tar xjf "$file"     ;;
				*.tar.gz)    tar xzf "$file"     ;;
				*.bz2)       bunzip2 "$file"     ;;
				*.rar)       unrar x "$file"     ;;
				*.gz)        gunzip "$file"      ;;
				*.tar)       tar xf "$file"      ;;
				*.tbz2)      tar xjf "$file"     ;;
				*.tgz)       tar xzf "$file"     ;;
				*.zip)       unzip "$file"       ;;
				*.Z)         uncompress "$file"  ;;
				*.7z)        7z x "$file"        ;;
				*)           echo "${C_RED}❌ '$file' cannot be extracted via extract().${C_NC}" ;;
			esac
		else
			echo "${C_RED}❌ '$file' is not a valid file.${C_NC}"
		fi
	done
	echo "${C_GREEN}✅ Extraction complete!${C_NC}"
}

# Inspect a port and optionally terminate the process using it
port() {
	if [[ "$1" == "help" || "$1" == "-h" || -z "$1" ]]; then
		echo "${C_CYAN}🔌 port${C_NC}: See what's running on a port and optionally kill it."
		echo "Usage: ${C_YELLOW}port <number> [kill]${C_NC}"
		echo "Examples:"
		echo "  port 8080       (Views processes on port 8080)"
		echo "  port 3000 kill  (Kills the process running on port 3000)"
		return 0
	fi

	local target_port=$1
	if [[ "$2" == "kill" ]]; then
		echo "${C_RED}Attempting to kill process on port $target_port...${C_NC}"
		local pid=$(lsof -t -i:"$target_port")
		if [[ -n "$pid" ]]; then
			kill -9 $pid
			echo "${C_GREEN}✅ Process $pid killed successfully.${C_NC}"
		else
			echo "${C_YELLOW}⚠️  No process found running on port $target_port.${C_NC}"
		fi
	else
		echo "${C_CYAN}Processes listening on port $target_port:${C_NC}"
		lsof -i :"$target_port" || echo "${C_YELLOW}No active processes on this port.${C_NC}"
	fi
}

# Display local, public, and approximate geolocation information for your IP
myip() {
	if [[ "$1" == "help" || "$1" == "-h" ]]; then
		echo "${C_CYAN}🌐 myip${C_NC}: Fetches your networking info."
		echo "Usage: ${C_YELLOW}myip${C_NC}"
		return 0
	fi

	echo "${C_CYAN}Fetching IP details...${C_NC}"
	local local_ip=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}' | xargs ipconfig getifaddr 2>/dev/null)
	[[ -z "$local_ip" ]] && local_ip="127.0.0.1"
	local public_ip=$(curl -s https://ifconfig.me)
	local geo_info=$(curl -s "https://ipinfo.io/${public_ip}/city")
	local country_info=$(curl -s "https://ipinfo.io/${public_ip}/country")

	echo "🏠 ${C_YELLOW}Local IP:${C_NC}  $local_ip"
	echo "🌍 ${C_YELLOW}Public IP:${C_NC} $public_ip"
	echo "📍 ${C_YELLOW}Location:${C_NC}  $geo_info, $country_info"
}

# Measure HTTP request timing and connection latency for a URL
pingmap() {
	if [[ "$1" == "help" || "$1" == "-h" || -z "$1" ]]; then
		echo "${C_CYAN}📍 pingmap${C_NC}: Detailed connection latency breakdown."
		echo "Usage: ${C_YELLOW}pingmap <url> ${C_NC}"
		echo "Example: pingmap google.com"
		return 0
	fi

	local url="$1"

	# Prepend https:// when the URL has no scheme
	[[ "$url" != http* ]] && url="https://$url"

	echo "${C_CYAN}Mapping network route to: $url${C_NC}"
	echo "----------------------------------------"
	curl -w "  HTTP Status   : %{http_code}\n  DNS Lookup    : %{time_namelookup}s\n  TCP Connect   : %{time_connect}s\n  TLS Handshake : %{time_appconnect}s\n  Pre-Transfer  : %{time_pretransfer}s\n  First Byte    : %{time_starttransfer}s\n----------------------------------------\n  ${C_GREEN}Total Time    : %{time_total}s${C_NC}\n\n" -o /dev/null -s "$url"
}

# Fetch terminal weather and forecast information with optional display formats
weather() {
	if [[ "$1" == "help" || "$1" == "-h" ]]; then
		echo "${C_CYAN}☁️  weather${C_NC}: Advanced terminal weather and forecast."
		echo "Usage: ${C_YELLOW}weather [options] [location]${C_NC}"
		echo ""
		echo "Options:"
		echo "  ${C_YELLOW}-s, --short${C_NC}    Single-line compact format (Temp & Condition)"
		echo "  ${C_YELLOW}-o, --oneline${C_NC}  Rich single-line format (Temp, Wind, Humidity)"
		echo "  ${C_YELLOW}-f, --forecast${C_NC} Detailed visual graph forecast"
		echo "  ${C_YELLOW}-m, --moon${C_NC}    Show current moon phase"
		echo ""
		echo "Examples:"
		echo "  weather London          (Default 3-day text forecast)"
		echo "  weather -o New York     (One-line rich weather)"
		echo "  weather -f              (Detailed forecast for your current IP)"
		return 0
	fi

	local format=""
	local args=()

	for arg in "$@"; do
		case "$arg" in
			-s|--short) format="?format=3" ;;
			-o|--oneline) format="?format=4" ;;
			-f|--forecast) format="?format=v2" ;;
			-m|--moon) format="?Moon" ;;
			-*)
				echo "${C_RED}❌ Unknown option: $arg${C_NC}"
				echo "Run ${C_YELLOW}weather -h${C_NC} for usage."
				return 1
				;;
			*) args+=("$arg") ;;
		esac
	done

	local loc="${args[*]}"
	loc="${loc// /+}"

	echo "${C_CYAN}Fetching weather data...${C_NC}"
	curl -s "https://wttr.in/${loc}${format}"
}

uvi() {
	uv venv --clear || return
	source .venv/bin/activate || return
	if [ -f "pyproject.toml" ]; then
		uv sync --all-extras --active --upgrade
	elif [ -f "requirements.txt" ]; then
		uv pip install -r requirements.txt
	elif [ -f "requirements-dev.txt" ]; then
		uv pip install -r requirements-dev.txt
	else
		echo "No requirements file found"
		return 1
	fi
}
nai() {
  helm template kubecost-nightly --repo https://kubecost.github.io/nightly-helm-chart kubecost \
  --set networkCosts.enabled=true \
  --set clusterController.enabled=true \
  --set global.platforms.cicd.skipSanityChecks=true \
    "$@" \
    --skip-tests | yq -r ".. | .image? | select(. != null)" | sort -u
}

# kubecost all images
kai() {
  helm template kubecost-ga --repo https://kubecost.github.io/kubecost kubecost \
    "$@" \
    --skip-tests | yq -r ".. | .image? | select(. != null)" | sort -u
}
kla() {
  if [[ -n $(kubectl get pods -l app=aggregator -o name 2>/dev/null) ]]; then
    kubectl logs -l app=aggregator -c aggregator --tail=-1
  else
    kubectl logs -l app=cost-analyzer -c aggregator --tail=-1
  fi
}
klap() {
  if [[ -n $(kubectl get pods -l app=aggregator -o name 2>/dev/null) ]]; then
    kubectl logs -l app=aggregator -c aggregator --previous
  else
    kubectl logs -l app=cost-analyzer -c aggregator --previous
  fi
}
klaf() {
  if [[ -n $(kubectl get pods -l app=aggregator -o name 2>/dev/null) ]]; then
    kubectl logs -l app=aggregator -c aggregator --tail=-1 --follow
  else
    kubectl logs -l app=cost-analyzer -c aggregator --tail=-1 --follow
  fi
}
cat() {
  if (( $+commands[bat] )) && [[ -t 1 && $# -gt 0 && "$1" != -* ]]; then
    bat --plain --paging=never "$@"
  else
    command cat "$@"
  fi
}
if [ "$(command -v eza)" ]; then
  alias ll='eza -l --color always --icons -a -s type'
  alias l='eza --color always --icons -a -s type'
  alias la='eza -l --color always --icons -a -s type'
  alias ls='eza -G  --color auto --icons -a -s type'
fi
scan_image() {
    emulate -L zsh

    local image="$1"
    local image_type="${2:-unknown}"

    if [[ -z "$image" ]]; then
      echo "Usage: scan_image <image> [image_type]" >&2
      return 2
    fi

    echo "Scanning $image_type image: $image"

    local tmpdir raw temp_result temp_combined
    tmpdir=$(mktemp -d) || return 1
    {
      raw="$tmpdir/trivy.json"
      temp_result="$tmpdir/result.json"
      temp_combined="$tmpdir/combined.json"

      command trivy image --format json --exit-code 0 --ignore-unfixed \
        --severity CRITICAL,HIGH,MEDIUM,LOW "$image" > "$raw" || return

      # command jq -M: aliases.zsh forces jq -C, which writes ANSI into .json files
      command jq -M --arg img "$image" --arg type "$image_type" '
        {
          "image": $img,
          "type": $type,
          "base_vulnerabilities": (
            [
              (.Results // [])[] |
              select(.Class == "os-pkgs") |
              .Vulnerabilities // []
            ] | flatten |
            group_by(.Severity) |
            map({
              severity: .[0].Severity,
              count: length,
              vulnerabilities: map({
                id: .VulnerabilityID,
                package: .PkgName,
                version: .InstalledVersion
              })
            })
          ),
          "binary_vulnerabilities": (
            [
              (.Results // [])[] |
              select(.Class == "lang-pkgs") |
              .Vulnerabilities // []
            ] | flatten |
            group_by(.Severity) |
            map({
              severity: .[0].Severity,
              count: length,
              vulnerabilities: map({
                id: .VulnerabilityID,
                package: .PkgName,
                version: .InstalledVersion
              })
            })
          )
        }' "$raw" > "$temp_result" || {
          echo "Error: failed to parse trivy JSON for $image" >&2
          return 1
        }

      [[ -f scan_results.json ]] || echo "[]" > scan_results.json

      command jq -M -s '.[0] + [.[1]]' scan_results.json "$temp_result" > "$temp_combined" || return
      mv "$temp_combined" scan_results.json
    } always {
      rm -rf -- "$tmpdir"
    }
  }
password_gen() {
	local str
	while true; do
		str=$(LC_ALL=C tr -dc 'a-zA-Z0-9_' < /dev/urandom | head -c 16)
		if [[ "$str" == *_* && "$str" != _* && "$str" != *_ ]]; then
			echo "$str"
			break
		fi
	done
}
### Make a directory and cd into it, parents included.
###   mkcd ~/src/new/project
### https://github.com/mattmc3/zephyr/blob/main/functions/mkcd
mdcd() {
  emulate -L zsh

  [[ -n "${1:-}" ]] || { print -ru2 -- "mkcd: expecting a directory argument"; return 1 }
  mkdir -p -- "$1" && builtin cd -- "$1"
}
mdtmpcd() {
  emulate -L zsh

  # The template is spelled out because GNU and BSD mktemp disagree about -t.
  local dir tmp=${${TMPDIR:-/tmp}%/}
  dir=$(mktemp -d "$tmp/${1:-tmp}.XXXXXXXX") || return 1
  builtin cd -- "$dir" && print -r -- "$PWD"
}
