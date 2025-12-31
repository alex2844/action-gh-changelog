#!/usr/bin/env bash

# Получает список коммитов через GitHub API.
# Поддерживает как диапазон (compare), так и список всех коммитов (commits),
# если начальный реф не указан.
# @param $1 api_url - URL API репозитория (например, https://api.github.com/repos/user/repo).
# @param $2 token - Токен авторизации GitHub.
# @param $3 from_ref - Начальный тег/хеш (может быть пустым для начала истории).
# @param $4 to_ref - Конечный тег/хеш.
function get_api_commits() {
	local api_url="$1"
	local token="$2"
	local from_ref="$3"
	local to_ref="$4"
	local url="${api_url}/commits"
	if [[ -n "${from_ref}" ]]; then
		url="${api_url}/compare/${from_ref}...${to_ref}"
	fi

	local response_body=$(curl -s \
		-H "Accept: application/vnd.github.v3+json" \
		-H "Authorization: Bearer ${token}" \
		"${url}"
	)

	local api_error=$(echo "${response_body}" | jq -r 'if type=="object" and .message then .message else "" end' 2>/dev/null)
	if [[ -n "${api_error}" ]]; then
		if [[ "${api_error}" == "Not Found" ]]; then
			log warn "$(t "warn_api_fetch_failed")"
			return 1
		else
			log error "$(t "error_api_returned" "${api_error}")"
		fi
	fi

	echo "${response_body}" | jq -r '
		(if type=="array" then . else .commits end)[] |
		.sha[0:7] as $h |
		"\($h)|\($h)|" + (.commit.message | split("\n")[0]) + "|" + (.author.login // .commit.author.name)
	'
}
