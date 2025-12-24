#!/usr/bin/env bash

load_locate() {
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

t() {
	local key="$1"
	shift
	printf "${I18N[${key}]:-${key}}" "$@"
}
