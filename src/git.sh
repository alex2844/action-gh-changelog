#!/usr/bin/env bash

readonly GIT_LOG_DELIMITER="###GIT_ENTRY_START###"

# Получает и парсит коммиты из локального репозитория в заданном диапазоне тегов.
# @param $1 from_ref - Начальный тег/коммит.
# @param $2 to_ref - Конечный тег/коммит (по умолчанию HEAD).
# @param $3 reverse_mode - `true` для вывода в хронологическом порядке.
function get_local_commits_by_tag() {
	local from_ref="$1"
	local to_ref="${2:-HEAD}"
	local reverse_mode="${3:-false}"
	local reverse_arg=""
	"${reverse_mode}" && reverse_arg="--reverse"
	git log --no-merges ${reverse_arg} --pretty=format:"%n###GIT_ENTRY_START###%n%H|%an%n%B" "${from_ref}".."${to_ref}" 2>/dev/null | parse_git_log || true
	git log --no-merges ${reverse_arg} --pretty=format:"%n${GIT_LOG_DELIMITER}%n%H|%an%n%B" "${from_ref}".."${to_ref}" 2>/dev/null | parse_git_log || true
}

# Получает и парсит коммиты из локального репозитория за указанный период.
# @param $1 since_date - Начальная дата.
# @param $2 until_date - Конечная дата.
# @param $3 reverse_mode - `true` для вывода в хронологическом порядке.
function get_local_commits_by_date() {
	local since_date="${1:-}"
	local until_date="${2:-}"
	local reverse_mode="${3:-false}"
	local reverse_arg=""
	local date_args=()
	[[ -n "${since_date}" ]] && date_args+=(--since="${since_date}")
	[[ -n "${until_date}" ]] && date_args+=(--until="${until_date}")
	"${reverse_mode}" && reverse_arg="--reverse"
	git log --no-merges ${reverse_arg} --pretty=format:"%n${GIT_LOG_DELIMITER}%n%H|%an%n%B" "${date_args[@]}" 2>/dev/null | parse_git_log || true
}

# Низкоуровневый парсер вывода `git log`.
# "Распаковывает" squashed-коммиты и преобразует Revert-коммиты.
# Ожидает на вход специфичный формат с разделителем ###GIT_ENTRY_START###.
function parse_git_log() {
	local state="init"
	local outer_hash=""
	local outer_author=""
	local current_hash=""
	local current_author=""
	local is_squashed=0
	local found_subject_for_normal=0
	local found_inner_msg=0
	local squash_idx=0

	while IFS= read -r line; do
		if [[ "${line}" == "${GIT_LOG_DELIMITER}" ]]; then
			state="header"
			is_squashed=0
			found_subject_for_normal=0
			squash_idx=0
			continue
		fi
		if [[ "${state}" == "header" ]]; then
			outer_hash="${line%%|*}"
			outer_hash="${outer_hash:0:7}"
			outer_author="${line#*|}"
			current_hash="${outer_hash}"
			current_author="${outer_author}"
			state="body"
			continue
		fi
		if [[ "${state}" == "body" ]]; then
			if [[ "${line}" =~ "Squashed commit of the following:" ]]; then
				is_squashed=1
				current_hash="${outer_hash}"
				current_author="${outer_author}"
				found_inner_msg=0
				continue
			fi
			if [[ "${is_squashed}" -eq 1 ]]; then
				local clean_line=$(trim "${line}")
				[[ -z "${clean_line}" ]] && continue
				if [[ "${clean_line}" =~ ^commit[[:space:]]+([a-f0-9]+) ]]; then
					current_hash="${BASH_REMATCH[1]}"
					current_hash="${current_hash:0:7}"
					current_author="${outer_author}"
					found_inner_msg=0
					continue
				fi
				if [[ "${clean_line}" =~ ^Author:[[:space:]]*(.*) ]]; then
					local full_auth="${BASH_REMATCH[1]}"
					if [[ "${full_auth}" =~ ^([^<]+) ]]; then
						current_author=$(trim "${BASH_REMATCH[1]}")
					else
						current_author="${full_auth}"
					fi
					continue
				fi
				[[ "${clean_line}" =~ ^Date: ]] && continue
				[[ "${clean_line}" == "Squashed commit of the following:" ]] && continue
				if [[ "${found_inner_msg}" -eq 0 ]] && [[ "${line}" =~ ^[[:space:]] ]]; then
					local final_hash="${current_hash}"
					if [[ "${final_hash}" == "${outer_hash}" ]]; then
						squash_idx=$((squash_idx + 1))
						final_hash="${outer_hash}_${squash_idx}"
					fi
					echo "${final_hash}|${clean_line}|${current_author}"
					found_inner_msg=1
				fi
			else
				if [[ "${found_subject_for_normal}" -eq 0 ]] && [[ -n "${line}" ]]; then
					local clean_line=$(trim "${line}")
					if [[ -n "${clean_line}" ]]; then
						if [[ "${clean_line}" =~ ^Revert[[:space:]]+\"(.+)\" ]]; then
							clean_line="revert: ${BASH_REMATCH[1]}"
						fi
						echo "${outer_hash}|${clean_line}|${outer_author}"
						found_subject_for_normal=1
					fi
				fi
			fi
		fi
	done
}
