#!/usr/bin/env bash
set -euo pipefail
readonly __source="${BASH_SOURCE:-$0}"
readonly __filename="$(basename -- "${__source}")"
readonly __dirname="$(dirname "$(readlink -e "${__source}")")"
readonly __invoke="${0/#\/*/${__filename}}"
readonly __version='main'

source "${__dirname}/i18n.sh"
source "${__dirname}/utils.sh"
source "${__dirname}/commits.sh"
source "${__dirname}/remote.sh"
source "${__dirname}/semver.sh"

# Выводит текст справки (usage) и успешно завершает работу скрипта.
function usage() {
	log "$(t "usage_header" "${__invoke}")"
	log "$(t "usage_opt_t")"
	log "$(t "usage_opt_o")"
	log "$(t "usage_opt_s")"
	log "$(t "usage_opt_u")"
	log "$(t "usage_opt_r")"
	log "$(t "usage_opt_l")"
	log "$(t "usage_opt_n")"
	log "$(t "usage_opt_q")"
	log "$(t "usage_opt_v")"
	log "$(t "usage_opt_h")"
	exit 0
}

# Проверяет наличие базовых утилит, необходимых для работы скрипта.
# В случае отсутствия завершает работу с ошибкой.
function check_deps() {
	for dep in git; do
		if ! command -v "${dep}" &>/dev/null; then
			error "$(t "error_dep_missing" "${dep}")"
		fi
	done
}

# Главная функция-оркестратор.
# @param $@ - Аргументы командной строки, переданные скрипту.
function main() {
	local raw_args="$*"
	local output_file=""
	local target_tag=""
	local since_date=""
	local until_date=""
	local raw_list_mode=false
	local show_links=false
	local show_next_version=false
	load_locate "${LANG%_*}"

	local flags="output:o tag:t since:s until:u raw:r links:l next-version:n quiet:q help:h version:v"
	eval "$(normalize_args "${flags}" "$@")"
	while getopts ":o:t:s:u:lrnqhv" OPT; do
		case ${OPT} in
			o) output_file=${OPTARG};;
			t) target_tag=${OPTARG};;
			s) since_date=${OPTARG};;
			u) until_date=${OPTARG};;
			r) raw_list_mode=true;;
			l) show_links=true;;
			n) show_next_version=true;;
			q) QUIET_MODE=true;;
			h) usage;;
			v) print_version;;
			\?) error "$(t "error_invalid_flag" "$(resolve_flag "${OPTARG}" "${OPTIND}" "${flags}" "${raw_args}" "$@")")";;
			:) error "$(t "error_flag_requires_arg" "$(resolve_flag "${OPTARG}" "${OPTIND}" "${flags}" "${raw_args}" "$@")")";;
		esac
	done

	check_deps

	detect_remote_provider
	determine_range "${since_date}" "${until_date}" "${target_tag}"

	if "${show_next_version}"; then
		local raw_commits=$(fetch_commits_data "false")
		calculate_next_version "${PREVIOUS_TAG}" "${raw_commits}"
		return
	fi

	local processed_commits=$(process_commits "${raw_list_mode}" "${show_links}")
	if [[ -z "${processed_commits}" ]]; then
		log "$(t "log_no_commits_found")"
		exit 0
	fi

	local changelog_content=$(generate_changelog_content "${processed_commits}" "${raw_list_mode}")
	if [[ -n "${output_file}" ]]; then
		echo -e "${changelog_content}" > "${output_file}"
		log success "$(t "log_saved_to_file" "${output_file}")"
	else
		${QUIET_MODE} || changelog_content="\n${changelog_content}"
		echo -e "${changelog_content}"
	fi
}

if [[ "${__source}" == "$0" ]]; then
	main "$@"
fi
