#!/usr/bin/env bash
set -euo pipefail

SDMS_HOME="${SDMS_HOME:-"$(dirname "$(readlink -f "$0")")"}"
SDMS_SRC="${SDMS_SRC:-"$SDMS_HOME/packages"}"
SDMS_DEST="${SDMS_DEST:-"$HOME"}"

help() {
	echo -e "Simple Dotfiles Management Script

\e[33mUsage:\e[0m sdms [COMMAND] [OPTIONS] [ARGS]

\e[33mCommands:\e[0m
  \e[32mnew (alias: n)\e[0m <package name>
    Create a new package with the specified name.
  \e[32mlink (alias: l)\e[0m <package name>
    Link all files of the specified package that are under the 'pfx' folder.
  \e[32munlink (alias: ul)\e[0m <package name>
    Unlink all files of the specified package that are under the 'pfx' folder.
  \e[32mrun-scripts (alias: r)\e[0m <package name>
    Run all executable scripts under 'scripts' of the specified package.
  \e[32mgo (alias: g)\e[0m <package name>
    Create a new subshell inside the root directory of the specified package.
  \e[32mlink-file (alias: lf)\e[0m <file>
    Create a relative symbolic link of a package's prefix file inside the
    directory specified by 'SDMS_DEST' according to the relative directory
    structure of the file.
  \e[32munlink-file (alias: ulf)\e[0m <file>
    Unlink a file that is part of a package. This file can be either the link
    or the file that the symlink points to inside the package's 'pfx' folder.
  \e[32maddto (alias: a)\e[0m <package name> <file>
    Add a file to a package's 'pfx' folder.
  \e[32mrename (alias: rn)\e[0m <file>
    Rename a file that is part of a package's linked files. The file parameter
    can be either the symlink in the destination or the file itself inside the
    package's 'pfx' folder.
"
}

error() {
	echo -e "\e[1m\e[31merror\e[0m: $*" >&2
	exit 1
}

get_all_package_names() {
	find "$SDMS_SRC" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -printf '%f\n'
}

new_package() {
	for pkgname; do
		mkdir -pv "$SDMS_SRC/$pkgname"
		mkdir -pv "$SDMS_SRC/$pkgname/pfx"
		mkdir -pv "$SDMS_SRC/$pkgname/scripts"
		mkdir -pv "$SDMS_SRC/$pkgname/deps"
		printf "%s\n" "# $pkgname" "" > "$SDMS_SRC/$pkgname/README.md"
	done
}

add_file_to_package() {
	local pkgname="$1"
	local file="$2"

	[ ! -e "$file" ] && error "'$file' does not exist."
	[ -L "$file" ] && error "Symlinks can not be added to a package."
	[ -d "$file" ] && error "Directories can not be added to a package."

	local filepath
	filepath="$(readlink -f "$file")"
	[[ ! "$filepath" =~ ^"$SDMS_DEST" ]] && error "Files that are not inside 'SDMS_DEST' can not be added to a package."

	local pkgpfx="$SDMS_SRC/$pkgname/pfx"
	local pkgfile="${filepath/"$SDMS_DEST"/"$pkgpfx"}"

	mkdir -pv "$(dirname "$pkgfile")"
	mv -v "$filepath" "$pkgfile"
	ln -srv "$pkgfile" "$filepath"
}

rename_package_file() {
	local file="$1"
	local newname="$2"

	local pkgfile
	pkgfile="$(readlink -f "$file")"
	[[ ! "$pkgfile" =~ ^"$SDMS_SRC".*/pfx ]] && error "'$file' is not a symlink to a sdms package file."

	local newpkgfile
	newpkgfile="$(dirname "$pkgfile")/$newname"

	local filelink="$SDMS_DEST/${pkgfile#*pfx/}"
	if [ -e "$filelink" ]; then
		unlink_package_file "$pkgfile"
		mv "$pkgfile" "$newpkgfile"
		link_package_file "$newpkgfile"
	else
		mv "$pkgfile" "$newpkgfile"
	fi
}

link_package_file() {
	local pkgfile
	pkgfile="$(readlink -f "$1")"
	[[ ! "$pkgfile" =~ ^"$SDMS_SRC".*/pfx ]] && error "'$file' is not a symlink to a sdms package file."

	local filelink
	filelink="$SDMS_DEST/${pkgfile#*pfx/}"

	if [ -L "$filelink" ] && [ "$(readlink -f "$filelink")" == "$pkgfile" ]; then
		ln -srvf "$pkgfile" "$filelink"
	else
		ln -srvb "$pkgfile" "$filelink"
	fi
}

link_package() {
	local pkgnames
	if [ $# -eq 0 ]; then
		mapfile -t pkgnames < <(get_all_package_names)
	else
		pkgnames=("$@")
	fi
	for pkgname in "${pkgnames[@]}"; do
		local pkgpfx="$SDMS_SRC/$pkgname/pfx"
		[ ! -d "$pkgpfx" ] && continue
		find "$pkgpfx" -type f -print0 | while IFS= read -d '' -r pkgfile; do
			link_package_file "$pkgfile"
		done
	done
}

unlink_package_file() {
	local file="$1"

	[ ! -e "$file" ] && echo "'$file' does not exist." && return
	[ -d "$file" ] && error "Directories are not a valid argument."

	local filepath
	filepath="$(readlink -f "$file")"
	[[ ! "$filepath" =~ ^"$SDMS_SRC".*/pfx ]] && error "'$file' is not a symlink to a sdms package file."

	local filelink
	if [ -L "$file" ]; then
		filelink="$file"
	else
		filelink="$SDMS_DEST/${filepath#*pfx/}"
	fi

	unlink "$filelink"
}

unlink_package() {
	local pkgnames
	if [ $# -eq 0 ]; then
		mapfile -t pkgnames < <(get_all_package_names)
	else
		pkgnames=("$@")
	fi
	for pkgname in "${pkgnames[@]}"; do
		local pkgpfx="$SDMS_SRC/$pkgname/pfx"
		find "$pkgpfx" -type f -print0 | while IFS= read -d '' -r pkgfile; do
			unlink_package_file "$pkgfile"
		done
	done
}

go_to_package_dir() {
	[ $# -gt 1 ] && error "'sdms go' accepts none or just one argument."
	if [ $# -eq 0 ]; then
		(cd "$SDMS_SRC" && $SHELL)
	elif [ $# -eq 1 ]; then
		(cd "$SDMS_SRC/$1" && $SHELL)
	fi
}

run_package_scripts() {
	local pkgnames
	if [ $# -eq 0 ]; then
		mapfile -t pkgnames < <(get_all_package_names)
	else
		pkgnames=("$@")
	fi
	for pkgname in "${pkgnames[@]}"; do
		[ -d "$SDMS_SRC/$pkgname" ] || error "'$pkgname' is not a package."
		[ -d "$SDMS_SRC/$pkgname/scripts" ] || continue
		for file in "$SDMS_SRC/$pkgname"/scripts/*.sh; do
			if [ -x "$file" ]; then
				"$file"
			else
				echo "Skipping '$file' because it is not executable."
			fi
		done
	done
}

if [ $# -eq 0 ]; then
	help
	exit 1
fi

command="$1"
shift

case "$command" in
	--help | -h | help | h) help "$@" ;;

	addto | a) add_file_to_package "$@" ;;
	rename | rn) rename_package_file "$@" ;;
	link-file | lf) link_package_file "$@" ;;
	unlink-file | ulf) unlink_package_file "$@" ;;

	new | n) new_package "$@" ;;
	link | l) link_package "$@" ;;
	unlink | ul) unlink_package "$@" ;;
	run-scripts | r) run_package_scripts "$@" ;;
	go | g) go_to_package_dir "$@" ;;

	*) error "'$command' is not a command." ;;
esac
