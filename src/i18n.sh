#!/usr/bin/env bash

declare -gA I18N

# Загружает языковой пакет (.sh файл) на основе кода локали.
# Определяет язык по ru/be/uk кодам, для всех остальных использует английский.
# @param $1 locale - Код локали (например, "ru" или "en").
function load_locate() {
	local locale="$1"
	case "${locale}" in
		ru*|be*|uk*)
			source "${__dirname}/locales/ru.sh"
		;;
		*)
			source "${__dirname}/locales/en.sh"
		;;
	esac
}

# Возвращает переведенную строку по ключу.
# Если ключ не найден, возвращает сам ключ.
# Поддерживает форматирование в стиле `printf`.
# @param $1 key - Ключ для поиска в массиве I18N.
# @param $@ (остальные) - Аргументы для подстановки в строку через `printf`.
function t() {
	local key="$1"
	shift
	printf "${I18N[${key}]:-${key}}" "$@"
}
