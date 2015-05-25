#!/bin/sh

case $- in
  *i*)
    ;;
  *)
    set -eu
    ;;
esac

grep_packages() {
  chdist --data-dir "${debci_data_basedir}/chdist" grep-dctrl-packages ${debci_suite}-${debci_arch} "$@"
}

grep_sources() {
  chdist --data-dir "${debci_data_basedir}/chdist" grep-dctrl-sources ${debci_suite}-${debci_arch} "$@"
}


list_binaries() {
  pkg="$1"
  grep_sources -n -s Binary -F Package -X "$pkg" | sed -s 's/, /\n/g' | sort -u
}


list_packages_from_archive() {
  grep_sources -n -s Package -F Testsuite autopkgtest | sort | uniq
}


get_maintainers() {
  local pkg="$1"
  grep_sources -n -s Maintainer,Uploaders -F Package -X "$pkg"  | sed -e 's/,\s*/\n/g' | sed -e 's/.*<\(.*\)>.*/\1/; /^$/d'
}


get_packages_by_maintainer() {
  local maintainer_email="$1"
  grep_sources -n -s Package -F Maintainer,Uploaders "<$maintainer_email>" | sort -u
}


first_banner=
banner() {
  if [ "$first_banner" = "$pkg" ]; then
    echo
  fi
  first_banner="$pkg"
  echo "$@" | sed -e 's/./—/g'
  echo "$@"
  echo "$@" | sed -e 's/./—/g'
  echo
}

indent() {
  sed -e 's/^/    /'
}

autopkgtest_dir_for_package() {
  local pkg="$1"
  pkg_dir=$(echo "$pkg" | sed -e 's/\(\(lib\)\?.\).*/\1\/&/')
  echo "${debci_autopkgtest_dir}/${pkg_dir}"
}

autopkgtest_incoming_dir_for_package() {
  local pkg="$1"
  pkg_dir=$(echo "$pkg" | sed -e 's/\(\(lib\)\?.\).*/\1\/&/')
  echo "${debci_autopkgtest_incoming_dir}/${pkg_dir}"
}

status_dir_for_package() {
  local pkg="$1"
  pkg_dir=$(echo "$pkg" | sed -e 's/\(\(lib\)\?.\).*/\1\/&/')
  echo "${debci_packages_dir}/${pkg_dir}"
}


log() {
  if [ "$debci_quiet" = 'false' ]; then
    echo "$@"
  fi
}


report_status() {
  if [ "$debci_quiet" = 'true' ]; then
    return
  fi
  local pkg="$1"
  local status="$2"
  local duration="${3:-}"
  if [ -t 1 ]; then
    case "$status" in
      skip)
        color=8
        ;;
      pass)
        color=2
        ;;
      fail)
        color=1
        ;;
      tmpfail|requested)
        color=3
        ;;
      *)
        color=5 # should never get here though
        ;;
    esac
    log "${pkg} \033[38;5;${color}m${status}\033[m" "$duration"
  else
    log "$pkg" "$status" "$duration"
  fi >&2
}


command_available() {
  which "$1" >/dev/null 2>/dev/null
}

# Makes sure $lockfile exists, and is owned by the debci user
ensure_lockfile() {
  local lockfile="$1"
  if [ ! -f "$lockfile" ]; then
    touch "$lockfile"
    chown $debci_user:$debci_group "$lockfile"
  fi
}

run_with_lock_or_exit() {
  local lockfile="$1"
  ensure_lockfile "$lockfile"
  shift
  (
    flock --nonblock 9 || exit 0
    "$@"
  ) 9> "$lockfile"
}

run_with_shared_lock() {
  local lockfile="$1"
  shift
  ensure_lockfile "$lockfile"
  flock --shared "$lockfile" "$@"
}

run_with_exclusive_lock() {
  local lockfile="$1"
  shift
  ensure_lockfile "$lockfile"
  flock --exclusive "$lockfile" "$@"
}
