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

# Выводит текст справки (usage) и успешно завершает работу скрипта.
function usage() {
	log "$(t "usage_header" "${__invoke}")"
	log "$(t "usage_opt_t")"
	log "$(t "usage_opt_o")"
	log "$(t "usage_opt_s")"
	log "$(t "usage_opt_u")"
	log "$(t "usage_opt_l")"
	log "$(t "usage_opt_r")"
	log "$(t "usage_opt_q")"
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
	local output_file=""
	local target_tag=""
	local since_date=""
	local until_date=""
	local show_links=false
	local raw_list_mode=false
	load_locate "${LANG%_*}"

	while getopts ":o:t:s:u:rlqh" opt; do
		case ${opt} in
			o) output_file=${OPTARG};;
			t) target_tag=${OPTARG};;
			s) since_date=${OPTARG};;
			u) until_date=${OPTARG};;
			l) show_links=true;;
			r) raw_list_mode=true;;
			q) quiet_mode=true;;
			h) usage;;
			\?) error "$(t "error_invalid_flag" "${OPTARG}")";;
			:) error "$(t "error_flag_requires_arg" "${OPTARG}")";;
		esac
	done

	check_deps

	detect_remote_provider
	determine_range "${since_date}" "${until_date}" "${target_tag}"

	local processed_commits=$(process_commits "${raw_list_mode}" "${show_links}")
	if [[ -z "${processed_commits}" ]]; then
		log "$(t "log_no_commits_found")"
		exit 0
	fi

	log "$(t "log_changelog_generation_start")"
	local changelog_content=$(generate_changelog_content "${processed_commits}" "${raw_list_mode}")

	if [[ -n "${output_file}" ]]; then
		echo -e "${changelog_content}" > "${output_file}"
		log "$(t "log_saved_to_file" "${output_file}")"
	else
		${quiet_mode} || changelog_content="\n${changelog_content}"
		echo -e "${changelog_content}"
	fi
}

if [[ "${__source}" == "$0" ]]; then
	main "$@"
fi
