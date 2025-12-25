#!/usr/bin/env bash

declare -g quiet_mode=false

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
