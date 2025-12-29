#!/usr/bin/env bash
set -euo pipefail

: "${INSTALL_DIR:="${HOME}/.local/bin"}"
readonly REPO="alex2844/action-gh-changelog"
readonly BINARY="changelog"

function log() {
	local level="${1:-debug}"
	local message="$@"
	if [[ $# -gt 0 ]]; then
		case "${level}" in
			error|warn|info|success|debug)
				shift
				message="$@"
			;;
		esac
	fi
	local color=""
	local reset="\033[0m"
	local icon=""
	case "${level}" in
		error) color="\033[0;31m"; icon="❌ ";;
		warn) color="\033[1;33m"; icon="⚠️  ";;
		info) icon="ℹ️  ";;
		success) icon="✅ ";;
	esac
	[[ ! -t 2 ]] && color=""
	echo -e "${color}${icon}${message}${color:+${reset}}" >&2
}

function error() {
	log error "$@"
	exit 1
}

function main() {
	local version="${1:-}"
	local url="https://github.com/${REPO}/releases/latest/download/${BINARY}"
	[[ -n "${version}" ]] && url="https://github.com/${REPO}/releases/download/${version}/${BINARY}"
	command -v curl >/dev/null 2>&1 || error "curl is required but not found."

	if [[ ! -d "${INSTALL_DIR}" ]]; then
		log info "Creating directory ${INSTALL_DIR}..."
		mkdir -p "${INSTALL_DIR}" || error "Failed to create directory."
	fi

	log info "Installing ${BINARY}..."
	if ! curl --fail --location --progress-bar --output "${INSTALL_DIR}/${BINARY}" "${url}" 2>/dev/null; then
		error "Failed to download ${BINARY} from \"${url}\""
	fi
	chmod +x "${INSTALL_DIR}/${BINARY}" || error "Failed to set executable permissions."
	"${INSTALL_DIR}/${BINARY}" --version >/dev/null 2>&1 || error "Installation check failed."
	log success "Successfully installed to: ${INSTALL_DIR}/${BINARY}"

	case ":${PATH}:" in
		*":${INSTALL_DIR}:"*);;
		*)
			echo
			log warn "Warning: '${INSTALL_DIR}' is not in your PATH."
			echo "To use '${BINARY}' globally, add this to your shell config:"
			echo
			echo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
			echo
		;;
	esac
}

main "$@"
