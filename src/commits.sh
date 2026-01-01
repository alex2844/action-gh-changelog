#!/usr/bin/env bash

source "${__dirname}/git.sh"

declare -g PREVIOUS_TAG=""
declare -g TARGET_TAG=""
declare -g SINCE_DATE=""
declare -g UNTIL_DATE=""

# Получает предыдущий тег относительно указанного
# @param $1 current_tag - Текущий тег
# @return Выводит предыдущий тег или пустую строку
function get_previous_tag() {
	local current_tag="$1"
	local all_tags=$(git tag --sort=version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
	if [[ -z "${all_tags}" ]]; then
		return
	fi
	
	local found_current=false
	local prev=""
	while IFS= read -r tag; do
		if [[ "${tag}" == "${current_tag}" ]]; then
			found_current=true
			break
		fi
		prev="${tag}"
	done <<<"${all_tags}"
	
	if ${found_current} && [[ -n "${prev}" ]]; then
		echo "${prev}"
	fi
}

# Определяет диапазон коммитов (по тегам или датам) на основе аргументов.
# Устанавливает глобальные переменные:
#   SINCE_DATE, UNTIL_DATE
#   PREVIOUS_TAG, TARGET_TAG
# @param $1 arg_since - Значение флага -s.
# @param $2 arg_until - Значение флага -u.
# @param $3 arg_tag - Значение флага -t.
function determine_range() {
	local arg_since="$1"
	local arg_until="$2"
	local arg_tag="$3"

	SINCE_DATE=""
	UNTIL_DATE=""
	PREVIOUS_TAG=""
	TARGET_TAG=""

	if [[ -n "${arg_since}" ]] || [[ -n "${arg_until}" ]]; then
		log info "$(t "log_mode_by_date")"
		SINCE_DATE="${arg_since}"
		UNTIL_DATE="${arg_until}"
		local date_range_info
		if [[ -n "${SINCE_DATE}" ]]; then
			date_range_info=$(t "log_range_from" "${SINCE_DATE}")
		else
			date_range_info=$(t "log_range_from_beginning")
		fi
		[[ -n "${UNTIL_DATE}" ]] && date_range_info+="$(t "log_range_to" "${UNTIL_DATE}")"
		log success "$(t "log_range_defined" "${date_range_info}")"
	else
		log group "$(t "log_range_discovery")"
		if [[ -n "${arg_tag}" ]]; then
			[[ "${arg_tag}" != "v"* ]] && arg_tag="v${arg_tag}"
			if ! git rev-parse -q --verify "refs/tags/${arg_tag}" &>/dev/null; then
				error "$(t "error_tag_not_found" "${arg_tag}")"
			fi
			TARGET_TAG="${arg_tag}"
			PREVIOUS_TAG=$(get_previous_tag "${arg_tag}")
			log info "$(t "log_tag_from_arg" "${TARGET_TAG}")"
			if [[ -n "${PREVIOUS_TAG}" ]]; then
				log success "$(t "log_range_defined" "$(t "log_range_from_to" "${PREVIOUS_TAG}" "${TARGET_TAG}")")"
			else
				log success "$(t "log_range_defined" "$(t "log_range_from_beginning")$(t "log_range_to" "${TARGET_TAG}")")"
			fi
		else
			local latest_tag=$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
			if [[ -z "${latest_tag}" ]]; then
				log info "$(t "log_no_tags_found")"
				PREVIOUS_TAG=""
				TARGET_TAG="HEAD"
			else
				local commits_after_tag=$(git rev-list "${latest_tag}..HEAD" --count 2>/dev/null || echo "0")
				if [[ "${commits_after_tag}" -gt 0 ]]; then
					log info "$(t "log_commits_after_tag" "${commits_after_tag}" "${latest_tag}")"
					log info "$(t "log_generating_for_unreleased")"
					PREVIOUS_TAG="${latest_tag}"
					TARGET_TAG="HEAD"
					log success "$(t "log_range_defined" "$(t "log_range_from_to" "${PREVIOUS_TAG}" "HEAD")")"
				else
					log info "$(t "log_no_commits_after_tag" "${latest_tag}")"
					TARGET_TAG="${latest_tag}"
					PREVIOUS_TAG=$(get_previous_tag "${latest_tag}")
					if [[ -n "${PREVIOUS_TAG}" ]]; then
						log success "$(t "log_range_defined" "$(t "log_range_from_to" "${PREVIOUS_TAG}" "${TARGET_TAG}")")"
					else
						log success "$(t "log_range_defined" "$(t "log_range_from_beginning")$(t "log_range_to" "${TARGET_TAG}")")"
					fi
				fi
			fi
		fi
		log groupEnd
	fi
}

# Агрегирует получение "сырых" коммитов из локального репозитория и,
# если применимо, из удаленного API.
# @param $1 raw_list_mode - `true` для вывода в хронологическом порядке.
# @return Многострочная переменная с коммитами в формате "хеш|сообщение|автор".
function fetch_commits_data() {
	local raw_list_mode="${1:-false}"
	local all_commits=""

	log group "$(t "log_commits_fetching")"
	log info "$(t "log_commits_fetching_local")"

	if [[ -n "${SINCE_DATE}" ]] || [[ -n "${UNTIL_DATE}" ]]; then
		all_commits=$(get_local_commits_by_date "${SINCE_DATE}" "${UNTIL_DATE}" "${raw_list_mode}")
		local remote_commits=""
		if remote_commits=$(get_remote_commits_by_date "${SINCE_DATE}" "${UNTIL_DATE}"); then
			all_commits=$(printf "%s\n%s" "${all_commits}" "${remote_commits}")
		fi
	else
		all_commits=$(get_local_commits_by_tag "${PREVIOUS_TAG}" "${TARGET_TAG}" "${raw_list_mode}")
		local remote_commits=""
		if remote_commits=$(get_remote_commits_by_tag "${PREVIOUS_TAG}" "${TARGET_TAG}"); then
			all_commits=$(printf "%s\n%s" "${all_commits}" "${remote_commits}")
		fi
	fi
	log success "$(t "log_commits_processed")"
	log groupEnd
	echo "${all_commits}"
}

# Высокоуровневая "пайплайн" функция.
# Выполняет получение, дедупликацию и базовое форматирование коммитов.
# @param $1 raw_list_mode - `true` для вывода в хронологическом порядке.
# @param $2 show_links - `true` если нужно генерировать ссылки на коммиты
# @return Отформатированный и дедуплицированный список коммитов.
function process_commits() {
	local raw_list_mode="$1"
	local show_links="${2:-false}"
	local all_commits=$(fetch_commits_data "${raw_list_mode}")
	if [[ -z "${all_commits}" ]]; then
		return
	fi

	log group "$(t "log_deduplication_start")"
	local formatted_commits=$(deduplicate_and_format_commits "${all_commits}" "${show_links}")
	log success "$(t "log_deduplication_done")"
	log groupEnd

	echo "${formatted_commits}"
}

# Форматирует "сырой" список коммитов в Markdown-список.
# Дедуплицирует коммиты и добавляет ссылки на авторов GitHub.
# @param $1 all_commits - Многострочная переменная с коммитами
# @param $2 show_links - `true` если нужно генерировать ссылки на коммиты
function deduplicate_and_format_commits() {
	local all_commits="$1"
	local show_links="${2:-false}"
	declare -A seen_hashes
	declare -A seen_messages
	declare -A author_links
	declare -A unpushed_map

	local unpushed_list=$(get_unpushed_commits)
	while read -r short_hash; do
		[[ -z "${short_hash}" ]] && continue
		unpushed_map["${short_hash}"]=1
	done <<<"${unpushed_list}"

	if "${show_links}" && [[ -n "${GIT_HOST}" ]]; then
		while IFS='|' read -r unique_hash display_hash message author; do
			[[ -z "${unique_hash}" ]] && continue
			if [[ "${author}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
				author_links["${unique_hash}"]="([${author}](https://${GIT_HOST}/${author}))"
			fi
		done <<<"${all_commits}"
	fi

	while IFS='|' read -r unique_hash display_hash message author; do
		local mask="-"
		[[ -z "${unique_hash}" ]] && continue
		if [[ -n "${seen_hashes[${unique_hash}]:-}" ]] || [[ -n "${seen_messages[${message}]:-}" ]]; then
			continue
		fi
		seen_hashes["${unique_hash}"]=1
		seen_messages["${message}"]=1

		local commit_hash_display="${display_hash}"
		if [[ -z "${unpushed_map[${display_hash}]:-}" ]]; then
			mask="*"
			if "${show_links}" && [[ -n "${GIT_HOST}" ]] && [[ -n "${REPO_PATH}" ]]; then
				local commit_url="https://${GIT_HOST}/${REPO_PATH}/commit/${display_hash}"
				commit_hash_display="[${display_hash}](${commit_url})"
			fi
		fi

		local author_info
		if [[ -n "${author_links[${unique_hash}]:-}" ]]; then
			author_info="${author_links[${unique_hash}]}"
		else
			author_info="(${author})"
		fi

		echo "${mask} ${commit_hash_display} ${message} ${author_info}"
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
	local commits=$(echo "${all_commits}" | grep -E "^(\*|-) [^ ]+ ${include_pattern}" || true)
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

	log group "$(t "log_changelog_generation_start")"
	if "${raw_list_mode}"; then
		log info "$(t "log_mode_raw_list")"
		changelog_content="${commits}"
	else
		log info "$(t "log_mode_grouped")"
		local section_content
		section_content=$(filter_commits "feat" "" "${commits}") && changelog_content+="$(t "section_features")\n${section_content}\n\n"
		section_content=$(filter_commits "fix" "fix\(ci\)" "${commits}") && changelog_content+="$(t "section_fixes")\n${section_content}\n\n"
		section_content=$(filter_commits "(refactor|perf)" "" "${commits}") && changelog_content+="$(t "section_improvements")\n${section_content}\n\n"
		section_content=$(filter_commits "revert" "" "${commits}" | sed -E 's/^([*-] [^ ]+) revert:[[:space:]]*/\1 /i') && changelog_content+="$(t "section_reverts")\n${section_content}\n\n"
		section_content=$(filter_commits "docs" "" "${commits}") && changelog_content+="$(t "section_docs")\n${section_content}\n\n"
		section_content=$(filter_commits "(ci|fix\(ci\)|chore\(ci\)|chore\(release\))" "" "${commits}") && changelog_content+="$(t "section_ci")\n${section_content}\n\n"
		section_content=$(filter_commits "chore" "chore\(ci\)|chore\(release\)|revert" "${commits}") && changelog_content+="$(t "section_misc")\n${section_content}\n\n"

		if [[ -n "${GIT_HOST}" ]] && [[ -n "${REPO_PATH}" ]]; then
			local changelog_link
			if [[ "${PREVIOUS_TAG}" == v* ]]; then
				changelog_link="https://${GIT_HOST}/${REPO_PATH}/compare/${PREVIOUS_TAG}...${TARGET_TAG}"
			else
				changelog_link="https://${GIT_HOST}/${REPO_PATH}/commits/${TARGET_TAG}"
			fi
			changelog_content+="$(t "footer_full_changelog"): ${changelog_link}"
		else
			changelog_content=$(echo -e "${changelog_content}" | sed 's/\n\n$//')
		fi
	fi
	log success "$(t "log_changelog_generation_done")"
	log groupEnd
	echo "${changelog_content}"
}
