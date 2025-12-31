#!/usr/bin/env bash

# Получает список коммитов через GitHub API в заданном диапазоне тегов.
# Использует глобальные переменные TOKEN и REPO_PATH.
# @param $1 from_ref - Начальный тег/коммит (может быть пустым).
# @param $2 to_ref - Конечный тег/коммит.
function get_github_commits_by_tag() {
	local from_ref="$1"
	local to_ref="$2"
	local path="commits"
	if [[ -n "${from_ref}" ]]; then
		path="compare/${from_ref}...${to_ref}"
	fi

	local response_body=$(curl -s \
		-H "Accept: application/vnd.github.v3+json" \
		-H "Authorization: Bearer ${TOKEN}" \
		"https://api.github.com/repos/${REPO_PATH}/${path}"
	)

	process_github_response "${response_body}"
}

# Получает список коммитов через GitHub API за указанный период.
# Использует глобальные переменные TOKEN и REPO_PATH.
# @param $1 since_date - Начальная дата.
# @param $2 until_date - Конечная дата.
function get_github_commits_by_date() {
	local since_date="$1"
	local until_date="$2"
	
	local curl_args=()
	[[ -n "${since_date}" ]] && curl_args+=(-d "since=$(urlencode "${since_date}")")
	[[ -n "${until_date}" ]] && curl_args+=(-d "until=$(urlencode "${until_date}")")

	local response_body=$(curl -s -G \
		-H "Accept: application/vnd.github.v3+json" \
		-H "Authorization: Bearer ${TOKEN}" \
		"https://api.github.com/repos/${REPO_PATH}/commits" \
		"${curl_args[@]}"
	)

	process_github_response "${response_body}"
}

# Вспомогательная функция для обработки ответа API и вывода ошибок.
# @param $1 response_body - Тело ответа от curl.
function process_github_response() {
	local response_body="$1"

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
