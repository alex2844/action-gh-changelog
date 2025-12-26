#!/usr/bin/env bash

function get_api_commits() {
	local api_url="$1"
	local token="$2"
	local from_ref="$3"
	local to_ref="$4"

	local response_body=$(curl -s \
		-H "Accept: application/vnd.github.v3+json" \
		-H "Authorization: Bearer ${token}" \
		"${api_url}/compare/${from_ref}...${to_ref}"
	)

	if echo "${response_body}" | jq -e '.message' >/dev/null; then
		local error_msg=$(echo "${response_body}" | jq -r '.message')
		if [[ "${error_msg}" == "Not Found" ]]; then
			log "$(t "warn_api_fetch_failed")"
			return 1
		else
			error "$(t "error_api_returned" "${error_msg}")"
		fi
	fi

	echo "${response_body}" | jq -r '.commits[] | .sha[0:7] as $h | "\($h)|\($h)|" + (.commit.message | split("\n")[0]) + "|" + (.author.login // .commit.author.name)'
}
