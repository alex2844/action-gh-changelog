#!/usr/bin/env bash
set -euo pipefail

function usage() {
	echo "Использование: $0 [-t <tag>] [-o <output_file>] [-s <since_date>] [-u <until_date>] [-r] [-h]"
	echo "  -t <tag>            Тег, для которого генерируется changelog (по умолчанию: последний тег)."
	echo "  -o <output_file>    Файл для сохранения результата (по умолчанию: вывод на экран)."
	echo "  -s <since_date>     Начальная дата для выборки коммитов (например, '2025-01-01' или '1 year ago')."
	echo "  -u <until_date>     Конечная дата для выборки коммитов."
	echo "  -r                  Вывести коммиты в виде простого списка (без группировки)."
	echo "  -h                  Показать эту справку."
}

function error() {
	echo "❌ Ошибка: $1" >&2
	exit 1
}

function check_deps() {
	local missing_deps=0
	for dep in git awk; do
		if ! command -v "${dep}" &>/dev/null; then
			echo "❌ Утилита '${dep}' не найдена, но она необходима для работы скрипта." >&2
			missing_deps=1
		fi
	done
	return ${missing_deps}
}

function check_api_deps() {
	local missing_deps=0
	for dep in jq curl; do
		if ! command -v "${dep}" &>/dev/null; then
			echo "   - ⚠️  Утилита '${dep}' не найдена. Невозможно использовать GitHub API." >&2
			missing_deps=1
		fi
	done
	return ${missing_deps}
}

function deduplicate_and_format_commits() {
	local all_commits="$1"
	local git_host="$2"
	local formatted_commits=""
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

		formatted_commits+="* ${message} ${author_info}"$'\n'
	done <<< "${all_commits}"

	echo "${formatted_commits}"
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

	if echo "${response_body}" | jq -e '.message' > /dev/null; then
		local error_msg=$(echo "${response_body}" | jq -r '.message')
		if [[ "${error_msg}" == "Not Found" ]]; then
			echo "⚠️  Предупреждение: Не удалось получить данные через API. Возможно, один из тегов не существует в удаленном репозитории." >&2
			return 1
		else
			error "API вернул ошибку: ${error_msg}"
		fi
	fi

	echo "${response_body}" | jq -r '.commits[] | .sha[0:7] + "|" + (.commit.message | split("\n")[0]) + "|" + .author.login'
}

function get_local_commits_by_tag() {
	local from_ref="$1"
	local to_ref="$2"
	local reverse_mode="$3"
	local reverse_arg=""
	[[ "${reverse_mode}" == true ]] && reverse_arg="--reverse"
	git log --no-merges ${reverse_arg} --pretty=format:"%h|%s|%an" "${from_ref}".."${to_ref}" 2>/dev/null || true
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
	git log --no-merges ${reverse_arg} --pretty=format:'%h|%s|%an' "${date_args[@]}" 2>/dev/null || true
}

function main() {
	local output_file=""
	local target_tag_arg=""
	local since_date=""
	local until_date=""
	local raw_list_mode=false

	while getopts ":o:t:s:u:rh" opt; do
		case ${opt} in
			o ) output_file=${OPTARG};;
			t ) target_tag_arg=${OPTARG};;
			s ) since_date=${OPTARG};;
			u ) until_date=${OPTARG};;
			r ) raw_list_mode=true;;
			h ) usage; exit 0;;
			\? ) error "Неверный флаг: -${OPTARG}. Используйте -h для справки.";;
			: ) error "Флаг -${OPTARG} требует аргумент.";;
		esac
	done

	check_deps

	local use_api=false
	local git_host=""
	local repo_path=""
	if [[ -z "${since_date}" ]] && [[ -z "${until_date}" ]]; then
		echo "🔍 Определение репозитория..."
		local remote_url=$(git remote get-url origin 2>/dev/null || true)
		if [[ -n "${remote_url}" ]]; then
			if [[ "${remote_url}" =~ https://([^/]+)/(.+) || "${remote_url}" =~ git@([^:]+):(.+) ]]; then
				git_host="${BASH_REMATCH[1]}"
				repo_path="${BASH_REMATCH[2]}"
				repo_path=${repo_path%.git}
				echo "   - ✅ Удаленный репозиторий найден: ${git_host}/${repo_path}"
				if [[ "${git_host}" == "github.com" ]]; then
					echo "   - ℹ️  Обнаружен репозиторий GitHub. Проверка API-зависимостей..."
					if check_api_deps; then
						use_api=true
						echo "   - ✅ API-зависимости найдены."
					fi
				else
					echo "   - ℹ️  Обнаружен репозиторий на ${git_host}. Используются только локальные коммиты."
				fi
			else
				echo "   - ⚠️  Не удалось распознать формат удаленного URL: ${remote_url}"
			fi
		else
			echo "   - ⚠️  Удаленный репозиторий (origin) не найден. Используются только локальные коммиты."
		fi
	fi

	local token=""
	if [[ "${use_api}" == true ]]; then
		echo "🔍 Поиск токена GitHub..."
		if [[ -n "${GITHUB_TOKEN:-}" ]]; then
			token="${GITHUB_TOKEN}"
			echo "   - ✅ Найден в переменной окружения GITHUB_TOKEN."
		elif command -v gh &>/dev/null && gh auth status &>/dev/null; then
			token=$(gh auth token)
			echo "   - ✅ Найден через GitHub CLI (gh)."
		else
			echo "   - ⚠️  Токен GitHub не найден. Данные из API не будут загружены."
		fi
	fi

	echo "🔍 Определение диапазона..."
	local all_commits=""
	if [[ -n "${since_date}" ]] || [[ -n "${until_date}" ]]; then
		echo "   - ℹ️  Выбран режим генерации по датам."
		local date_range_info="с ${since_date:-начала истории}"
		[[ -n "${until_date}" ]] && date_range_info+=" по ${until_date}"
		echo "   - ✅ Диапазон: ${date_range_info}"
		echo "🔍 Получение коммитов..."
		echo "   - Получение локальных коммитов..."
		all_commits=$(get_local_commits_by_date "${since_date}" "${until_date}" "${raw_list_mode}")
	else
		local target_tag
		local previous_tag
		if [[ -n "${target_tag_arg}" ]]; then
			[[ "${target_tag_arg}" != "v"* ]] && target_tag_arg="v${target_tag_arg}"
			if ! git rev-parse -q --verify "refs/tags/${target_tag_arg}" &>/dev/null; then
				error "Тег '${target_tag_arg}' не найден в локальном репозитории."
			fi
			target_tag="${target_tag_arg}"
			previous_tag=$(git describe --tags --abbrev=0 "${target_tag}^" 2>/dev/null || git rev-list --max-parents=0 HEAD | head -n 1)
			echo "   - ℹ️  Используется тег из аргумента: ${target_tag}"
			echo "   - ✅ Диапазон: от ${previous_tag} до ${target_tag}"
		else
			if ! git describe --tags --abbrev=0 &>/dev/null; then
				echo "   - ℹ️  Теги не найдены, используются все коммиты от начала репозитория"
				previous_tag=$(git rev-list --max-parents=0 HEAD | head -n 1)
				target_tag="HEAD"
			else
				local latest_tag=$(git describe --tags --abbrev=0)
				local commits_after_tag=$(git rev-list "${latest_tag}..HEAD" --count 2>/dev/null || echo "0")
				if [[ "${commits_after_tag}" -gt 0 ]]; then
					echo "   - ℹ️  Найдено ${commits_after_tag} коммитов после последнего тега ${latest_tag}"
					echo "   - ℹ️  Генерируется changelog для нереализованных изменений"
					previous_tag="${latest_tag}"
					target_tag="HEAD"
					echo "   - ✅ Диапазон: от ${previous_tag} до HEAD"
				else
					echo "   - ℹ️  Коммитов после последнего тега не найдено, используется последний тег: ${latest_tag}"
					target_tag="${latest_tag}"
					previous_tag=$(git describe --tags --abbrev=0 "${target_tag}^" 2>/dev/null || git rev-list --max-parents=0 HEAD | head -n 1)
					echo "   - ✅ Диапазон: от ${previous_tag} до ${target_tag}"
				fi
			fi
		fi

		echo "🔍 Получение коммитов..."
		echo "   - Получение локальных коммитов..."
		all_commits=$(get_local_commits_by_tag "${previous_tag}" "${target_tag}" "${raw_list_mode}")
		if [[ "${use_api}" == true && -n "${token}" ]]; then
			echo "   - Попытка дополнения данными из GitHub API..."
			local github_commits=""
			local api_url="https://api.github.com/repos/${repo_path}"
			if github_commits=$(get_api_commits "${api_url}" "${token}" "${previous_tag}" "${target_tag}"); then
				echo "   - ✅ Данные из GitHub API получены, объединяем с локальными..."
				all_commits=$(printf "%s\n%s" "${all_commits}" "${github_commits}")
			else
				echo "   - ⚠️  Не удалось получить данные из API, используются только локальные коммиты"
			fi
		fi
	fi
	echo "   - ✅ Коммиты обработаны."

	if [[ -z "${all_commits}" ]]; then
		echo "⚪️ Не найдено коммитов для обработки."
		exit 0
	fi

	echo "🔍 Удаление дубликатов..."
	local commits=$(deduplicate_and_format_commits "${all_commits}" "${git_host}")
	echo "   - ✅ Дубликаты удалены."

	echo "🔍 Генерация списка изменений..."
	local changelog_content=""
	if [[ "${raw_list_mode}" == true ]]; then
		echo "   - ℹ️  Выбран режим вывода в виде простого списка."
		changelog_content="${commits}"
	else
		echo "   - ℹ️  Выбран режим группировки по разделам."
		local section_content
		section_content=$(get_commits "^\* feat" "" "${commits}") && changelog_content+="### 🚀 Новые возможности\n${section_content}\n\n"
		section_content=$(get_commits "^\* fix" "fix\(ci\)" "${commits}") && changelog_content+="### 🐛 Исправления\n${section_content}\n\n"
		section_content=$(get_commits "^\* refactor" "" "${commits}") && changelog_content+="### ✨ Улучшения и оптимизация\n${section_content}\n\n"
		section_content=$(get_commits "^\* docs" "" "${commits}") && changelog_content+="### 📖 Документация\n${section_content}\n\n"
		section_content=$(get_commits "^\* ci|fix\(ci\)|chore\(ci\)|chore\(release\)" "" "${commits}") && changelog_content+="### ⚙️ CI/CD\n${section_content}\n\n"
		section_content=$(get_commits "^\* chore" "chore\(ci\)|chore\(release\)" "${commits}") && changelog_content+="### 🔧 Прочее\n${section_content}\n\n"

		if [[ -n "${git_host}" ]] && [[ -n "${repo_path}" ]]; then
			local changelog_link
			if [[ "${previous_tag}" == v* ]]; then
				changelog_link="https://${git_host}/${repo_path}/compare/${previous_tag}...${target_tag}"
			else
				changelog_link="https://${git_host}/${repo_path}/commits/${target_tag}"
			fi
			changelog_content+="**Full Changelog**: ${changelog_link}"
		else
			changelog_content=$(echo -e "${changelog_content}" | sed 's/\n\n$//')
		fi
	fi
	echo "   - ✅ Список изменений сгенерирован."

	if [[ -n "${output_file}" ]]; then
		echo -e "${changelog_content}" > "${output_file}"
		echo "   - ✅ Список изменений сохранен в файл: ${output_file}"
	else
		echo && echo -e "${changelog_content}"
	fi
}

main "$@"
