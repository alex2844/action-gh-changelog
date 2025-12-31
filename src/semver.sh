#!/usr/bin/env bash

# Парсит версию (v1.2.3) на компоненты major, minor, patch
# @param $1 version_string
function parse_version() {
	local ver="${1#v}"
	if [[ -z "${ver}" ]]; then
		echo "0 0 0"
		return
	fi
	if [[ "${ver}" =~ ^([0-9]+)(\.([0-9]+))?(\.([0-9]+))?$ ]]; then
		local major="${BASH_REMATCH[1]}"
		local minor="${BASH_REMATCH[3]:-0}"
		local patch="${BASH_REMATCH[5]:-0}"
		echo "${major} ${minor} ${patch}"
	else
		echo "0 0 0"
	fi
}

# Вычисляет следующую версию на основе списка коммитов
# @param $1 current_version
# @param $2 commits (формат: hash|hash|message|author)
function calculate_next_version() {
	local current_ver="$1"
	local commits="$2"
	local bump_major=false
	local bump_minor=false
	local bump_patch=false
	
	log group "$(t "log_calculating_next_version")"
	read -r major minor patch <<<"$(parse_version "${current_ver}")"

	while IFS='|' read -r _ _ msg _; do
		[[ -z "${msg}" ]] && continue
		if [[ "${msg}" =~ ^[a-zA-Z0-9_-]+(\(.+\))?!: ]]; then
			bump_major=true
			break
		elif [[ "${msg}" =~ ^feat(\(.+\))?: ]]; then
			bump_minor=true
		elif [[ "${msg}" =~ ^(fix|refactor|perf)(\(.+\))?: ]]; then
			bump_patch=true
		fi
	done <<<"${commits}"
	log groupEnd

	if "${bump_major}"; then
		major=$((major + 1))
		minor=0
		patch=0
	elif "${bump_minor}"; then
		minor=$((minor + 1))
		patch=0
	elif "${bump_patch}"; then
		patch=$((patch + 1))
	fi
	echo "v${major}.${minor}.${patch}"
}
