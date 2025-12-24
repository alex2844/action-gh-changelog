#!/usr/bin/env bash
set -euo pipefail
readonly __source="${BASH_SOURCE:-$0}"
readonly __filename="$(basename -- "${__source}")"
readonly __dirname="$(dirname "$(readlink -e "${__source}")")"
readonly __invoke="${0/#\/*/${__filename}}"
readonly __version='main'

source "${__dirname}/i18n.sh"

QUIET_MODE=false

function usage() {
	log "$(t "usage_header" "${__invoke}")"
	log "$(t "usage_opt_t")"
	log "$(t "usage_opt_o")"
	log "$(t "usage_opt_s")"
	log "$(t "usage_opt_u")"
	log "$(t "usage_opt_r")"
	log "$(t "usage_opt_q")"
	log "$(t "usage_opt_h")"
	exit 0
}

function log() {
	if [[ "${QUIET_MODE}" == false ]]; then
		echo -e "$@" >&2
	fi
}

function error() {
	echo "$(t "error_prefix") $@" >&2
	exit 1
}

function trim() {
	local var="$*"
	var="${var#"${var%%[![:space:]]*}"}"
	var="${var%"${var##*[![:space:]]}"}"
	echo -n "${var}"
}

function check_deps() {
	for dep in git; do
		if ! command -v "${dep}" &>/dev/null; then
			error "$(t "error_dep_missing" "${dep}")"
		fi
	done
}

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

function deduplicate_and_format_commits() {
	local all_commits="$1"
	local git_host="$2"
	declare -A seen_hashes
	declare -A seen_messages
	declare -A author_links

	if [[ "${git_host}" == "github.com" ]]; then
		while IFS='|' read -r hash message author; do
			[[ -z "${hash}" ]] && continue
			if [[ "${author}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
				author_links["${hash}"]="([${author}](https://${git_host}/${author}))"
			fi
		done <<< "${all_commits}"
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
	done <<< "${all_commits}"
}

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

	echo "${response_body}" | jq -r '.commits[] | .sha[0:7] + "|" + (.commit.message | split("\n")[0]) + "|" + .author.login'
}

function get_commits() {
	local include_pattern="$1"
	local exclude_pattern="${2:-}"
	local all_commits="$3"
	local commits=$(echo "${all_commits}" | grep -E "${include_pattern}" || true)
	if [[ -n "${exclude_pattern}" ]]; then
		commits=$(echo "${commits}" | grep -E -v "${exclude_pattern}" || true)
	fi
	[[ -n "${commits}" ]] && echo "${commits}"
}

function get_local_commits_by_tag() {
	local from_ref="$1"
	local to_ref="$2"
	local reverse_mode="$3"
	local reverse_arg=""
	[[ "${reverse_mode}" == true ]] && reverse_arg="--reverse"
	git log --no-merges ${reverse_arg} --pretty=format:"%n###GIT_ENTRY_START###%n%h|%an%n%B" "${from_ref}".."${to_ref}" 2>/dev/null | parse_git_log || true
}

function get_local_commits_by_date() {
	local since_date="$1"
	local until_date="$2"
	local reverse_mode="$3"
	local reverse_arg=""
	local date_args=()
	[[ -n "${since_date}" ]] && date_args+=(--since="${since_date}")
	[[ -n "${until_date}" ]] && date_args+=(--until="${until_date}")
	[[ "${reverse_mode}" == true ]] && reverse_arg="--reverse"
	git log --no-merges ${reverse_arg} --pretty=format:"%n###GIT_ENTRY_START###%n%h|%an%n%B" "${date_args[@]}" 2>/dev/null | parse_git_log || true
}

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
		if [[ "${line}" == "###GIT_ENTRY_START###" ]]; then
			state="header"
			is_squashed=0
			found_subject_for_normal=0
			squash_idx=0
			continue
		fi
		if [[ "${state}" == "header" ]]; then
			outer_hash="${line%%|*}"
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

function main() {
	local output_file=""
	local target_tag_arg=""
	local since_date=""
	local until_date=""
	local raw_list_mode=false
	load_locate "${LANG%_*}"

	while getopts ":o:t:s:u:rqh" opt; do
		case ${opt} in
			o) output_file=${OPTARG};;
			t) target_tag_arg=${OPTARG};;
			s) since_date=${OPTARG};;
			u) until_date=${OPTARG};;
			r) raw_list_mode=true;;
			q) QUIET_MODE=true;;
			h) usage;;
			\?) error "$(t "error_invalid_flag" "${OPTARG}")";;
			:) error "$(t "error_flag_requires_arg" "${OPTARG}")";;
		esac
	done

	check_deps

	local use_api=false
	local git_host=""
	local repo_path=""
	if [[ -z "${since_date}" ]] && [[ -z "${until_date}" ]]; then
		log "$(t "log_repo_discovery")"
		local remote_url=$(git remote get-url origin 2>/dev/null || true)
		if [[ -n "${remote_url}" ]]; then
			if [[ "${remote_url}" =~ https://([^/]+)/(.+) || "${remote_url}" =~ git@([^:]+):(.+) ]]; then
				git_host="${BASH_REMATCH[1]}"
				repo_path="${BASH_REMATCH[2]}"
				repo_path=${repo_path%.git}
				log "$(t "log_repo_found" "${git_host}/${repo_path}")"
				if [[ "${git_host}" == "github.com" ]]; then
					log "$(t "log_repo_is_github")"
					if check_api_deps; then
						use_api=true
						log "$(t "log_api_deps_ok")"
					fi
				else
					log "$(t "log_repo_is_other_host" "${git_host}")"
				fi
			else
				log "$(t "warn_remote_url_unrecognized" "${remote_url}")"
			fi
		else
			log "$(t "warn_remote_origin_missing")"
		fi
	fi

	local token=""
	if [[ "${use_api}" == true ]]; then
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

	log "$(t "log_range_discovery")"
	local all_commits=""
	if [[ -n "${since_date}" ]] || [[ -n "${until_date}" ]]; then
		log "$(t "log_mode_by_date")"
		local date_range_info
		if [[ -n "${since_date}" ]]; then
			date_range_info=$(t "log_range_from" "${since_date}")
		else
			date_range_info=$(t "log_range_from_beginning")
		fi
		[[ -n "${until_date}" ]] && date_range_info+="$(t "log_range_to" "${until_date}")"
		log "$(t "log_range_defined" "${date_range_info}")"
		log "$(t "log_commits_fetching")"
		log "$(t "log_commits_fetching_local")"
		all_commits=$(get_local_commits_by_date "${since_date}" "${until_date}" "${raw_list_mode}")
	else
		local target_tag
		local previous_tag
		if [[ -n "${target_tag_arg}" ]]; then
			[[ "${target_tag_arg}" != "v"* ]] && target_tag_arg="v${target_tag_arg}"
			if ! git rev-parse -q --verify "refs/tags/${target_tag_arg}" &>/dev/null; then
				error "$(t "error_tag_not_found" "${target_tag_arg}")"
			fi
			target_tag="${target_tag_arg}"
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

		log "$(t "log_commits_fetching")"
		log "$(t "log_commits_fetching_local")"
		all_commits=$(get_local_commits_by_tag "${previous_tag}" "${target_tag}" "${raw_list_mode}")
		if [[ "${use_api}" == true && -n "${token}" ]]; then
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

	if [[ -z "${all_commits}" ]]; then
		log "$(t "log_no_commits_found")"
		exit 0
	fi

	log "$(t "log_deduplication_start")"
	local commits=$(deduplicate_and_format_commits "${all_commits}" "${git_host}")
	log "$(t "log_deduplication_done")"

	log "$(t "log_changelog_generation_start")"
	local changelog_content=""
	if [[ "${raw_list_mode}" == true ]]; then
		log "$(t "log_mode_raw_list")"
		changelog_content="${commits}"
	else
		log "$(t "log_mode_grouped")"
		local section_content
		section_content=$(get_commits "^\* feat" "" "${commits}") && changelog_content+="$(t "section_features")\n${section_content}\n\n"
		section_content=$(get_commits "^\* fix" "fix\(ci\)" "${commits}") && changelog_content+="$(t "section_fixes")\n${section_content}\n\n"
		section_content=$(get_commits "^\* refactor|perf" "" "${commits}") && changelog_content+="$(t "section_improvements")\n${section_content}\n\n"
		section_content=$(get_commits "^\* revert" "" "${commits}" | sed -E 's/^\* revert:[[:space:]]*/\* /i') && changelog_content+="$(t "section_reverts")\n${section_content}\n\n"
		section_content=$(get_commits "^\* docs" "" "${commits}") && changelog_content+="$(t "section_docs")\n${section_content}\n\n"
		section_content=$(get_commits "^\* ci|fix\(ci\)|chore\(ci\)|chore\(release\)" "" "${commits}") && changelog_content+="$(t "section_ci")\n${section_content}\n\n"
		section_content=$(get_commits "^\* chore" "chore\(ci\)|chore\(release\)|revert" "${commits}") && changelog_content+="$(t "section_misc")\n${section_content}\n\n"

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

	if [[ -n "${output_file}" ]]; then
		echo -e "${changelog_content}" > "${output_file}"
		log "$(t "log_saved_to_file" "${output_file}")"
	else
		[[ "${QUIET_MODE}" == false ]] && changelog_content="\n${changelog_content}"
		echo -e "${changelog_content}"
	fi
}

main "$@"
