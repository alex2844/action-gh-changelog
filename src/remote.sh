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
