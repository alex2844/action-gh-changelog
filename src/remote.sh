#!/usr/bin/env bash

source "${__dirname}/api/github.sh"

declare -g USE_API=false
declare -g GIT_HOST=""
declare -g REPO_PATH=""
declare -g TOKEN=""

# Проверяет наличие утилит (jq, curl), необходимых для работы с API.
# @return 0 если все зависимости найдены, 1 в противном случае.
function check_api_deps() {
	local missing_deps=0
	for dep in jq curl; do
		if ! command -v "${dep}" &>/dev/null; then
			log warn "$(t "warn_api_dep_missing" "${dep}")"
			missing_deps=1
		fi
	done
	return ${missing_deps}
}

# Вспомогательная функция для определения имени провайдера из хоста.
# github.com -> github
function get_provider_name() {
	echo "${GIT_HOST%%.*}"
}

# Получает список коммитов из удаленного репозитория (через API) в диапазоне тегов.
# Автоматически выбирает нужного провайдера (github, gitlab и т.д.).
# @param $1 from_ref - Начальный тег/коммит.
# @param $2 to_ref - Конечный тег/коммит.
# @return Выводит список коммитов в stdout, возвращает 0 при успехе.
function get_remote_commits_by_tag() {
	local from_ref="$1"
	local to_ref="$2"
	if ! "${USE_API}" || [[ -z "${TOKEN}" ]] || [[ -z "${GIT_HOST}" ]]; then
		return 1
	fi
	local provider=$(get_provider_name)
	local func_name="get_${provider}_commits_by_tag"
	if ! command -v "${func_name}" &>/dev/null; then
		return 1
	fi
	log info "$(t "log_api_fetching_attempt")"

	local output
	if output=$("${func_name}" "${from_ref}" "${to_ref}"); then
		log success "$(t "log_api_fetch_ok")"
		echo "${output}"
		return 0
	else
		log warn "$(t "warn_api_fetch_failed_fallback")"
		return 1
	fi
}

# Получает список коммитов из удаленного репозитория (через API) за период.
# @param $1 since_date - Начальная дата.
# @param $2 until_date - Конечная дата.
# @return Выводит список коммитов в stdout, возвращает 0 при успехе.
function get_remote_commits_by_date() {
	local since_date="$1"
	local until_date="$2"
	if ! "${USE_API}" || [[ -z "${TOKEN}" ]] || [[ -z "${GIT_HOST}" ]]; then
		return 1
	fi
	local provider=$(get_provider_name)
	local func_name="get_${provider}_commits_by_date"
	if ! command -v "${func_name}" &>/dev/null; then
		return 1
	fi
	log info "$(t "log_api_fetching_attempt")"

	local output
	if output=$("${func_name}" "${since_date}" "${until_date}"); then
		log success "$(t "log_api_fetch_ok")"
		echo "${output}"
		return 0
	else
		log warn "$(t "warn_api_fetch_failed_fallback")"
		return 1
	fi
}

# Определяет удаленный репозиторий, провайдера (GitHub) и подготавливает
# окружение для работы с API.
# Устанавливает глобальные переменные:
#   USE_API, TOKEN, GIT_HOST, REPO_PATH
function detect_remote_provider() {
	GIT_HOST=""
	REPO_PATH=""

	log group "$(t "log_repo_discovery")"
	local remote_url=$(git remote get-url origin 2>/dev/null || true)
	if [[ -z "${remote_url}" ]]; then
		log warn "$(t "warn_remote_origin_missing")"
		log groupEnd
		return
	fi

	if [[ "${remote_url}" =~ https://([^/]+)/(.+) ]] || [[ "${remote_url}" =~ git@([^:]+):(.+) ]]; then
		GIT_HOST="${BASH_REMATCH[1]}"
		REPO_PATH="${BASH_REMATCH[2]%.git}"
		log success "$(t "log_repo_found" "${GIT_HOST}/${REPO_PATH}")"
	else
		log warn "$(t "warn_remote_url_unrecognized" "${remote_url}")"
		return
	fi

	if [[ "${GIT_HOST}" == "github.com" ]]; then
		log info "$(t "log_repo_is_github")"
		if check_api_deps; then
			USE_API=true
			log success "$(t "log_api_deps_ok")"
		fi
	else
		log info "$(t "log_repo_is_other_host" "${GIT_HOST}")"
	fi

	if "${USE_API}"; then
		log group "$(t "log_token_search")"
		if [[ -n "${GITHUB_TOKEN:-}" ]]; then
			TOKEN="${GITHUB_TOKEN}"
			log success "$(t "log_token_found_env")"
		elif command -v gh &>/dev/null && gh auth status &>/dev/null; then
			TOKEN=$(gh auth token)
			log success "$(t "log_token_found_gh")"
		else
			log warn "$(t "warn_token_missing")"
		fi
		log groupEnd
	fi
	log groupEnd
}
