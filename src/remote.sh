#!/usr/bin/env bash

source "${__dirname}/api/github.sh"

declare -g use_api=false
declare -g token=""

# Проверяет наличие утилит (jq, curl), необходимых для работы с API.
# @return 0 если все зависимости найдены, 1 в противном случае.
function check_api_deps() {
	local missing_deps=0
	for dep in jq curl; do
		if ! command -v "${dep}" &>/dev/null; then
			log "$(t "warn_api_dep_missing" "${dep}")"
			missing_deps=1
		fi
	done
	return ${missing_deps}
}

# Определяет удаленный репозиторий, провайдера (GitHub) и подготавливает
# окружение для работы с API.
# Устанавливает глобальные переменные:
#   use_api, token, git_host, repo_path
function detect_remote_provider() {
	git_host=""
	repo_path=""

	log "$(t "log_repo_discovery")"
	local remote_url=$(git remote get-url origin 2>/dev/null || true)
	if [[ -z "${remote_url}" ]]; then
		log "$(t "warn_remote_origin_missing")"
		return
	fi

	if [[ "${remote_url}" =~ https://([^/]+)/(.+) ]] || [[ "${remote_url}" =~ git@([^:]+):(.+) ]]; then
		git_host="${BASH_REMATCH[1]}"
		repo_path="${BASH_REMATCH[2]%.git}"
		log "$(t "log_repo_found" "${git_host}/${repo_path}")"
	else
		log "$(t "warn_remote_url_unrecognized" "${remote_url}")"
		return
	fi

	if [[ "${git_host}" == "github.com" ]]; then
		log "$(t "log_repo_is_github")"
		if check_api_deps; then
			use_api=true
			log "$(t "log_api_deps_ok")"
		fi
	else
		log "$(t "log_repo_is_other_host" "${git_host}")"
	fi

	if "${use_api}"; then
		log "$(t "log_token_search")"
		if [[ -n "${GITHUB_TOKEN:-}" ]]; then
			token="${GITHUB_TOKEN}"
			log "$(t "log_token_found_env")"
		elif command -v gh &>/dev/null && gh auth status &>/dev/null; then
			token=$(gh auth token)
			log "$(t "log_token_found_gh")"
		else
			log "$(t "warn_token_missing")"
		fi
	fi
}
