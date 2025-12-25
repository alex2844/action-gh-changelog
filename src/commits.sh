#!/usr/bin/env bash

source "${__dirname}/git.sh"

declare -g git_host=""
declare -g repo_path=""
declare -g previous_tag=""
declare -g target_tag=""
declare -g since_date=""
declare -g until_date=""

# Определяет диапазон коммитов (по тегам или датам) на основе аргументов.
# Устанавливает глобальные переменные:
#   since_date, until_date
#   previous_tag, target_tag
# @param $1 arg_since - Значение флага -s.
# @param $2 arg_until - Значение флага -u.
# @param $3 arg_tag - Значение флага -t.
function determine_range() {
	local arg_since="$1"
	local arg_until="$2"
	local arg_tag="$3"

	since_date=""
	until_date=""
	previous_tag=""
	target_tag=""

	if [[ -n "${arg_since}" ]] || [[ -n "${arg_until}" ]]; then
		log "$(t "log_mode_by_date")"
		since_date="${arg_since}"
		until_date="${arg_until}"
		local date_range_info
		if [[ -n "${since_date}" ]]; then
			date_range_info=$(t "log_range_from" "${since_date}")
		else
			date_range_info=$(t "log_range_from_beginning")
		fi
		[[ -n "${until_date}" ]] && date_range_info+="$(t "log_range_to" "${until_date}")"
		log "$(t "log_range_defined" "${date_range_info}")"
	else
		log "$(t "log_range_discovery")"
		if [[ -n "${arg_tag}" ]]; then
			[[ "${arg_tag}" != "v"* ]] && arg_tag="v${arg_tag}"
			if ! git rev-parse -q --verify "refs/tags/${arg_tag}" &>/dev/null; then
				error "$(t "error_tag_not_found" "${arg_tag}")"
			fi
			target_tag="${arg_tag}"
			previous_tag=$(git describe --tags --abbrev=0 "${target_tag}^" 2>/dev/null || git rev-list --max-parents=0 HEAD | head -n 1)
			log "$(t "log_tag_from_arg" "${target_tag}")"
			log "$(t "log_range_defined" "$(t "log_range_from_to" "${previous_tag}" "${target_tag}")")"
		else
			if ! git describe --tags --abbrev=0 &>/dev/null; then
				log "$(t "log_no_tags_found")"
				previous_tag=$(git rev-list --max-parents=0 HEAD | head -n 1)
				target_tag="HEAD"
			else
				local latest_tag=$(git describe --tags --abbrev=0)
				local commits_after_tag=$(git rev-list "${latest_tag}..HEAD" --count 2>/dev/null || echo "0")
				if [[ "${commits_after_tag}" -gt 0 ]]; then
					log "$(t "log_commits_after_tag" "${commits_after_tag}" "${latest_tag}")"
					log "$(t "log_generating_for_unreleased")"
					previous_tag="${latest_tag}"
					target_tag="HEAD"
					log "$(t "log_range_defined" "$(t "log_range_from_to" "${previous_tag}" "HEAD")")"
				else
					log "$(t "log_no_commits_after_tag" "${latest_tag}")"
					target_tag="${latest_tag}"
					previous_tag=$(git describe --tags --abbrev=0 "${target_tag}^" 2>/dev/null || git rev-list --max-parents=0 HEAD | head -n 1)
					log "$(t "log_range_defined" "$(t "log_range_from_to" "${previous_tag}" "${target_tag}")")"
				fi
			fi
		fi
	fi
}

# Агрегирует получение "сырых" коммитов из локального репозитория и,
# если применимо, из GitHub API.
# @param $1 raw_list_mode - `true` для вывода в хронологическом порядке.
# @return Многострочная переменная с коммитами в формате "хеш|сообщение|автор".
function fetch_commits_data() {
	local raw_list_mode="$1"
	local all_commits=""

	log "$(t "log_commits_fetching")"
	log "$(t "log_commits_fetching_local")"

	if [[ -n "${since_date}" ]] || [[ -n "${until_date}" ]]; then
		all_commits=$(get_local_commits_by_date "${since_date}" "${until_date}" "${raw_list_mode}")
	else
		all_commits=$(get_local_commits_by_tag "${previous_tag}" "${target_tag}" "${raw_list_mode}")
		if "${use_api}" && [[ -n "${token}" ]]; then
			log "$(t "log_api_fetching_attempt")"
			local github_commits=""
			local api_url="https://api.github.com/repos/${repo_path}"
			if github_commits=$(get_api_commits "${api_url}" "${token}" "${previous_tag}" "${target_tag}"); then
				log "$(t "log_api_fetch_ok")"
				all_commits=$(printf "%s\n%s" "${all_commits}" "${github_commits}")
			else
				log "$(t "warn_api_fetch_failed_fallback")"
			fi
		fi
	fi
	log "$(t "log_commits_processed")"
	echo "${all_commits}"
}

# Высокоуровневая "пайплайн" функция.
# Выполняет получение, дедупликацию и базовое форматирование коммитов.
# @param $1 raw_list_mode - `true` для вывода в хронологическом порядке.
# @return Отформатированный и дедуплицированный список коммитов.
function process_commits() {
	local raw_list_mode="$1"
	local all_commits=$(fetch_commits_data "${raw_list_mode}")
	if [[ -z "${all_commits}" ]]; then
		return
	fi

	log "$(t "log_deduplication_start")"
	local formatted_commits=$(deduplicate_and_format_commits "${all_commits}")
	log "$(t "log_deduplication_done")"

	echo "${formatted_commits}"
}

# Форматирует "сырой" список коммитов в Markdown-список.
# Дедуплицирует коммиты и добавляет ссылки на авторов GitHub.
# @param $1 all_commits - Многострочная переменная с коммитами в формате "хеш|сообщение|автор".
function deduplicate_and_format_commits() {
	local all_commits="$1"
	declare -A seen_hashes
	declare -A seen_messages
	declare -A author_links

	if [[ "${git_host}" == "github.com" ]]; then
		while IFS='|' read -r hash message author; do
			[[ -z "${hash}" ]] && continue
			if [[ "${author}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
				author_links["${hash}"]="([${author}](https://${git_host}/${author}))"
			fi
		done <<<"${all_commits}"
	fi

	while IFS='|' read -r hash message author; do
		[[ -z "${hash}" ]] && continue
		if [[ -n "${seen_hashes[${hash}]:-}" ]] || [[ -n "${seen_messages[${message}]:-}" ]]; then
			continue
		fi
		seen_hashes["${hash}"]=1
		seen_messages["${message}"]=1

		local author_info
		if [[ -n "${author_links[${hash}]:-}" ]]; then
			author_info="${author_links[${hash}]}"
		else
			author_info="(${author})"
		fi

		echo "* ${message} ${author_info}"
	done <<<"${all_commits}"
}

# Фильтрует отформатированный список коммитов по заданным паттернам.
# Используется для группировки коммитов по секциям.
# @param $1 include_pattern - Regex-паттерн для включения строк.
# @param $2 exclude_pattern - Regex-паттерн для исключения строк.
# @param $3 all_commits - Отформатированный список коммитов.
function filter_commits() {
	local include_pattern="$1"
	local exclude_pattern="${2:-}"
	local all_commits="$3"
	local commits=$(echo "${all_commits}" | grep -E "${include_pattern}" || true)
	if [[ -n "${exclude_pattern}" ]]; then
		commits=$(echo "${commits}" | grep -E -v "${exclude_pattern}" || true)
	fi
	[[ -n "${commits}" ]] && echo "${commits}"
}

# Генерирует финальный Markdown контент из отформатированного списка коммитов.
# Применяет группировку по секциям или выводит "сырой" список.
# @param $1 commits - Отформатированный список коммитов.
# @param $2 raw_list_mode - `true` для вывода простого списка.
# @return Готовый для вывода Markdown текст.
function generate_changelog_content() {
	local commits="$1"
	local raw_list_mode="${2:-false}"
	local changelog_content=""

	if "${raw_list_mode}"; then
		log "$(t "log_mode_raw_list")"
		changelog_content="${commits}"
	else
		log "$(t "log_mode_grouped")"
		local section_content
		section_content=$(filter_commits "^\* feat" "" "${commits}") && changelog_content+="$(t "section_features")\n${section_content}\n\n"
		section_content=$(filter_commits "^\* fix" "fix\(ci\)" "${commits}") && changelog_content+="$(t "section_fixes")\n${section_content}\n\n"
		section_content=$(filter_commits "^\* refactor|perf" "" "${commits}") && changelog_content+="$(t "section_improvements")\n${section_content}\n\n"
		section_content=$(filter_commits "^\* revert" "" "${commits}" | sed -E 's/^\* revert:[[:space:]]*/\* /i') && changelog_content+="$(t "section_reverts")\n${section_content}\n\n"
		section_content=$(filter_commits "^\* docs" "" "${commits}") && changelog_content+="$(t "section_docs")\n${section_content}\n\n"
		section_content=$(filter_commits "^\* ci|fix\(ci\)|chore\(ci\)|chore\(release\)" "" "${commits}") && changelog_content+="$(t "section_ci")\n${section_content}\n\n"
		section_content=$(filter_commits "^\* chore" "chore\(ci\)|chore\(release\)|revert" "${commits}") && changelog_content+="$(t "section_misc")\n${section_content}\n\n"

		if [[ -n "${git_host}" ]] && [[ -n "${repo_path}" ]]; then
			local changelog_link
			if [[ "${previous_tag}" == v* ]]; then
				changelog_link="https://${git_host}/${repo_path}/compare/${previous_tag}...${target_tag}"
			else
				changelog_link="https://${git_host}/${repo_path}/commits/${target_tag}"
			fi
			changelog_content+="$(t "footer_full_changelog"): ${changelog_link}"
		else
			changelog_content=$(echo -e "${changelog_content}" | sed 's/\n\n$//')
		fi
	fi
	log "$(t "log_changelog_generation_done")"
	echo "${changelog_content}"
}
