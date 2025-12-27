#!/usr/bin/env bash

declare -g quiet_mode=false

# Выводит текущую версию скрипта и завершает выполнение.
# Использует глобальную переменную __version.
function print_version() {
	echo "${__version}"
	exit 0
}

# Выводит сообщение в stderr, если не включен тихий режим.
# @param ... все аргументы будут выведены как одна строка.
function log() {
	if ! ${quiet_mode}; then
		echo -e "$@" >&2
	fi
}

# Выводит сообщение об ошибке в stderr и завершает скрипт с кодом 1.
# @param ... все аргументы будут выведены как одна строка.
function error() {
	echo "$(t "error_prefix") $@" >&2
	exit 1
}

# Удаляет пробельные символы в начале и в конце строки.
# @param $1 Строка для обработки.
function trim() {
	local var="$*"
	var="${var#"${var%%[![:space:]]*}"}"
	var="${var%"${var##*[![:space:]]}"}"
	echo -n "${var}"
}

# Универсальный парсер аргументов.
# Выводит строку команды "set -- ...", которую нужно выполнить через eval.
# @param $1 flags_map - Строка маппинга "output:o tag:t"
# @param $@ (остальные) - Аргументы скрипта
function normalize_args() {
	local flags_map=" --${1// / --} "
	local out="set --"
	shift
	for arg in "$@"; do
		local key="${arg}"
		local val=""
		local has_val=false
		case "${arg}" in
			--*=*)
				key="${arg%%=*}"
				val="${arg#*=}"
				has_val=true
			;;
		esac
		case "${flags_map}" in
			*" ${key}:"*)
				local temp="${flags_map#* ${key}:}"
				local short="-${temp%% *}"
				out="${out} '${short}'"
			;;
			*) out="${out} '${key//\'/\'\\\'\'}'";;
		esac
		if ${has_val}; then
			out="${out} '${val//\'/\'\\\'\'}'"
		fi
	done
	echo "${out}"
}

# Восстанавливает имя флага.
# @param $1 short_opt - Символ из getopts (OPTARG)
# @param $2 idx - Индекс из getopts (OPTIND)
# @param $3 flags_map - Карта флагов "output:o tag:t"
# @param $4 raw_args - Исходная строка всех аргументов ("$*")
# @param $@ - Позиционные аргументы
function resolve_flag() {
	local short_opt="$1"
	local idx="$2"
	local flags_map="$3"
	local raw_args="$4"
	shift 4
	if [[ "${short_opt}" = "-" ]] || [[ "${short_opt}" = "?" ]]; then
		local shifts=$((idx - 1))
		local i=1
		while [[ "${i}" -lt "${shifts}" ]] && [[ $# -gt 0 ]]; do
			shift
			i=$((i + 1))
		done
		if [[ -n "${1:-}" ]] && [[ "$1" == --* ]]; then
			echo "$1"
			return
		fi
	fi
	for pair in ${flags_map}; do
		local key="${pair%%:*}"
		local val="${pair#*:}"
		if [[ "${val}" = "${short_opt}" ]]; then
			case "${raw_args}" in
				*"--${key}"*)
					echo "--${key}"
					return
				;;
			esac
			echo "-${short_opt}"
			return
		fi
	done
	echo "-${short_opt}"
}
