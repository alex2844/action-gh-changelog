#!/usr/bin/env bash
set -euo pipefail
readonly __source="${BASH_SOURCE:-$0}"
readonly __filename="$(basename -- "${__source}")"
readonly __dirname="$(cd "$(dirname "$0")/src" && pwd)"
readonly __version="${1:-}"

readonly OUTPUT_FILE="./dist/changelog"
readonly ENTRY_POINT="./src/main.sh"
readonly ENTRY_DIR="$(dirname "${ENTRY_POINT}")"

source "${__dirname}/i18n.sh"
source "${__dirname}/utils.sh"

function bundle() {
	local file="$1"
	local file_dirname="$(dirname "${file}")"
	if [[ ! -f "${file}" ]]; then
		error "$(t "error_file_not_found" "${file}")"
	fi
	while IFS= read -r line || [[ -n "${line}" ]]; do
		local trimmed_line="$(trim "${line}")"
		if [[ -z "${trimmed_line}" ]] || [[ "${trimmed_line}" == \#* ]]; then
			if [[ "${file}" == "${ENTRY_POINT}" ]] && [[ "${line}" =~ ^#! ]]; then
				echo "${line}"
			fi
			continue
		fi
		if [[ "${line}" =~ ^([[:space:]]*)function[[:space:]]+(.*) ]]; then
			line="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
		fi
		if [[ "${line}" =~ ^readonly[[:space:]]+(__version|version|VERSION)=[\"\'].*[\"\'] ]] && [[ -n "${__version}" ]]; then
			echo "${line}" | sed -E "s/=.*/='${__version#v}'/"
		elif [[ "${line}" =~ ^([[:space:]]*)(source|\.)[[:space:]]+[\"\']?([^\"\'[:space:]]+)[\"\']? ]]; then
			local import_path="${BASH_REMATCH[3]}"
			if [[ "${import_path}" == *"\${__dirname}"* ]]; then
				import_path="${ENTRY_DIR}/${import_path#\$\{__dirname\}/}"
			elif [[ "${import_path}" == ./* ]]; then
				import_path="${file_dirname}/${import_path#./}"
			fi
			log "$(t "log_build_embedding" "${import_path}")"
			bundle "${import_path}"
		else
			echo "${line}"
		fi
	done <"${file}"
}

function main() {
	load_locate "${LANG%_*}"
	mkdir -p "$(dirname "${OUTPUT_FILE}")"
	log "$(t "log_build_start")"
	bundle "${ENTRY_POINT}" > "${OUTPUT_FILE}"
	chmod +x "${OUTPUT_FILE}"
	log "$(t "log_build_done" "${OUTPUT_FILE}")"
	log "$(t "log_build_check_ver")"
	if ! "${OUTPUT_FILE}" --version; then
		error "$(t "error_build_check_failed")"
	fi
}

if [[ "${__source}" == "$0" ]]; then
	main "$@"
fi
