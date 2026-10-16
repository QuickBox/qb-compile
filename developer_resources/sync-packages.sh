#!/usr/bin/env bash
################################################################################
# @file_name: sync-packages.sh
# @version: 1.0.8
# @description: Pull a codename's compiled .deb artifacts from a build server and
#   regenerate that codename's rows in compiled-packages/packages.lst. The whole
#   manifest is emitted in one canonical order (by codename, then category,
#   package, ascending version) so every sync leaves the file sorted. Run with
#   --canonicalize to reorder the manifest in place without a pull. The header
#   and fixed-width row bytes are preserved; running twice produces no change.
# @author: Jason Matthews (JMSolo)
# @license: MIT
# Copyright (C) 2019-2025, QuickBox.IO
#
# @save_tasks:
#  automated_versioning: true
#  automated_formatting: true
################################################################################
set -Eeuo pipefail

################################################################################
# @description: Defaults for every tunable. Overridden by qbcompile::sync::parse.
################################################################################
qbcompile::sync::defaults() {
  codename=""
  host=""
  port="22"
  dest="${PWD}/compiled-packages"
  dry_run="false"
  canonicalize="false"
  # Fixed-width column widths derived from the existing packages.lst header.
  # CODENAME 16, CATEGORY 28, PACKAGE 32, VERSION 23, FILENAME 57, MD5 32 (+4).
  row_format='%-16s%-28s%-32s%-23s%-57s%-32s    \n'
}

################################################################################
# @description: Usage banner.
################################################################################
qbcompile::sync::usage() {
  cat <<'EOF'
Usage: sync-packages.sh --codename <cn> --host <host> [options]
       sync-packages.sh --canonicalize [--dry-run]

Pulls a codename's compiled .deb tree from a build server and regenerates that
codename's rows in compiled-packages/packages.lst, re-sorting the whole file
into canonical order. --canonicalize re-sorts the existing manifest in place
with no pull (a pure reorder — no row content changes).

Required (sync mode):
  --codename <cn>    Distro codename to publish (e.g. bookworm, trixie, noble)
  --host <host>      Build server hostname the artifacts are pulled from
                     (not required with --dry-run)

Optional:
  --canonicalize     Reorder the existing packages.lst into canonical order and
                     exit. No pull, no --codename/--host needed. Honors --dry-run.
  --port <n>         SSH port for the pull (default: 22)
  --dest <path>      compiled-packages checkout (default: ./compiled-packages)
  --dry-run          Skip any write; print the packages.lst diff instead
  -h, --help         Show this help

Canonical order: rows are grouped by CODENAME, then CATEGORY, then PACKAGE, with
VERSION ascending; FILENAME and MD5 break remaining ties. A blank line separates
each (codename, category) block.

Auth is SSH-key based. Set RSYNC_RSH to override the transport; no credential is
ever embedded by this script.
EOF
}

################################################################################
# @description: Parse CLI arguments into the globals set by ::defaults.
################################################################################
qbcompile::sync::parse() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --codename)
      codename="${2:-}"
      shift 2
      ;;
    --host)
      host="${2:-}"
      shift 2
      ;;
    --port)
      port="${2:-}"
      shift 2
      ;;
    --dest)
      dest="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --canonicalize)
      canonicalize="true"
      shift
      ;;
    -h | --help)
      qbcompile::sync::usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      qbcompile::sync::usage >&2
      exit 1
      ;;
    esac
  done

  # --canonicalize reorders the existing manifest only; it needs no codename,
  # host, or .deb tree — just the packages.lst it rewrites.
  if [[ "${canonicalize}" == "false" ]]; then
    [[ -z "${codename}" ]] && {
      printf 'error: --codename is required (omit only with --canonicalize)\n' >&2
      exit 1
    }
    [[ "${dry_run}" == "false" && -z "${host}" ]] && {
      printf 'error: --host is required (omit only with --dry-run)\n' >&2
      exit 1
    }
  fi
  [[ ! -f "${dest}/packages.lst" ]] && {
    printf 'error: %s/packages.lst not found\n' "${dest}" >&2
    exit 1
  }
  return 0
}

################################################################################
# @description: rsync-pull the codename's packaged tree from the build server.
#   Copy only (no --delete): never prunes the build server. Skipped under --dry-run.
################################################################################
qbcompile::sync::pull() {
  if [[ "${dry_run}" == "true" ]]; then
    printf 'dry-run: skipping network pull; using existing %s/%s tree\n' "${dest}" "${codename}" >&2
    return 0
  fi
  local src="root@${host}:/opt/qb-compile/packaged/${codename}/"
  local dst="${dest}/${codename}/"
  mkdir -p "${dst}"
  printf 'pulling %s -> %s\n' "${src}" "${dst}" >&2
  # RSYNC_RSH wins when the caller sets it; otherwise default to the port flag.
  # (A command-line --rsh would override RSYNC_RSH, so fold the env var in here.)
  # Exclude the apt-index files (Packages/Packages.gz/Release): they are generated per-category on
  # the build server but no consumer uses them — QuickBox resolves packages via packages.lst only.
  # Pulling them would drag vestigial, quickly-stale metadata into the public compiled-packages repo.
  rsync -a \
    --exclude='Packages' --exclude='Packages.gz' --exclude='Release' \
    --rsh="${RSYNC_RSH:-ssh -p ${port}}" "${src}" "${dst}"
}

################################################################################
# @description: Reduce a control Version field to the VERSION column value.
#   Generic rule: strip a trailing Debian packaging revision "-<rev>build<...>"
#   or "-<rev>mod<...>" (e.g. -1build1, -2build1, -1build1+allmods, -1build1+webv1,
#   -1mod1). A version with no such revision (e.g. 2.7.1) is returned unchanged.
#   The mod form is the legacy transmission 2.94/3.00 component debs; keeping it
#   in VERSION made the CLI's exact --version pin miss.
#   qbittorrent-nox: also strip the "-lt<libtorrent>" qualifier so VERSION keeps
#   the bare upstream shape (5.1.2-lt2.0.11build1 -> 5.1.2). The lt qualifier
#   stays in FILENAME, so the artifact is unambiguous.
#   Known limitation: two lt-variants of ONE qbittorrent version in the same
#   codename (e.g. 5.1.4-lt2.0.11 and 5.1.4-lt2.0.12) collapse to duplicate
#   VERSION rows told apart only by FILENAME. The tree may hold exactly one
#   qbittorrent deb per codename, in which case this cannot arise.
# @arg $1 raw control version
# @arg $2 package name (optional)
################################################################################
qbcompile::sync::strip_version() {
  local raw="$1" package="${2:-}"
  [[ "${package}" == "qbittorrent-nox" ]] && raw="${raw%%-lt*}"
  printf '%s' "${raw}" | sed -E 's/-[0-9]+(build|mod)[0-9A-Za-z.+~-]*$//'
}

################################################################################
# @description: Walk the codename's .deb tree and emit one fixed-width row per
#   deb on stdout (the same 6-column shape as packages.lst). CATEGORY is the
#   parent directory name; PACKAGE/VERSION come from the deb control; FILENAME
#   is the basename; MD5 is md5sum. static-binary debs are excluded (binary-amd64
#   only). Ordering is handled downstream by ::canonical_sort.
################################################################################
qbcompile::sync::generate() {
  local tree="${dest}/${codename}/binary-amd64"
  [[ -d "${tree}" ]] || {
    printf 'error: %s not found (nothing to publish for %s)\n' "${tree}" "${codename}" >&2
    exit 1
  }
  local deb category package raw_version version filename md5
  local found="false"
  while IFS= read -r -d '' deb; do
    found="true"
    category="$(basename "$(dirname "${deb}")")"
    # qBittorrent ships as a STATIC BINARY that the QuickBox installer copies straight to
    # /usr/bin/qbittorrent-nox (chmod +x) — it is NOT dpkg-installed. Its packages.lst rows
    # therefore point at the static-binary/qbittorrent/*.amd64 files, curated by hand, and must
    # NEVER be regenerated from the .deb here (doing so points the installer at a .deb it copies verbatim,
    # producing a broken binary). Skip it; rebuild() preserves the existing qbittorrent rows.
    [[ "${category}" == "qbittorrent" ]] && continue
    # The tree dir name is the upstream package (xmlrpc-c), but the manifest
    # CATEGORY column is the query key consumers filter on (xmlrpc). Map it so a
    # sync emits the category the resolver actually queries.
    [[ "${category}" == "xmlrpc-c" ]] && category="xmlrpc"
    package="$(dpkg-deb -f "${deb}" Package)"
    raw_version="$(dpkg-deb -f "${deb}" Version)"
    version="$(qbcompile::sync::strip_version "${raw_version}" "${package}")"
    filename="$(basename "${deb}")"
    md5="$(md5sum "${deb}" | awk '{print $1}')"
    # shellcheck disable=SC2059
    printf "${row_format}" "${codename}" "${category}" "${package}" "${version}" "${filename}" "${md5}"
  done < <(find "${tree}" -mindepth 2 -maxdepth 2 -name '*.deb' -type f -print0 | sort -z)
  [[ "${found}" == "true" ]] || {
    printf 'error: no .deb files under %s\n' "${tree}" >&2
    exit 1
  }
}

################################################################################
# @description: THE single canonical ordering. Reads manifest data rows on
#   stdin (blank lines ignored) and writes them ordered by CODENAME, then
#   CATEGORY, then PACKAGE, with VERSION ascending; FILENAME then MD5 break any
#   remaining tie so the order is total and deterministic. A blank line
#   separates each (codename, category) block. Row bytes are preserved exactly
#   (a pure reorder) and the output is idempotent — feeding it back in is a
#   no-op. Both --canonicalize and the per-codename sync route rows through this.
################################################################################
qbcompile::sync::canonical_sort() {
  # Prefix each row with its six sort keys (tab-separated), sort on those keys,
  # then drop them — the trailing field is the untouched original row. PACKAGE
  # and VERSION use -V so soname/version numbers order numerically (libtorrent19
  # before libtorrent160, 5.0.2 before 5.1.0). LC_ALL=C keeps it locale-stable.
  awk 'NF > 0 { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $0 }' |
    LC_ALL=C sort -t $'\t' -k1,1 -k2,2 -k3,3V -k4,4V -k5,5 -k6,6 |
    awk -F '\t' '{
      grp = $1 SUBSEP $2
      if (NR > 1 && grp != prev) print ""
      print $7
      prev = grp
    }'
}

################################################################################
# @description: Rebuild packages.lst for the target codename.
#   - preserves the header verbatim
#   - keeps every other codename's rows unchanged
#   - swaps the target codename's rows for the freshly generated set
#   - re-sorts the whole body through ::canonical_sort, so the new rows land in
#     canonical position and the file never degrades out of order
#   Writes header + canonical body to stdout.
# @arg $1 path to a temp file of freshly generated rows for the target codename
################################################################################
qbcompile::sync::rebuild() {
  local genfile="$1"
  local manifest="${dest}/packages.lst"
  printf '%s\n' "$(head -n 1 "${manifest}")"
  {
    tail -n +2 "${manifest}" | awk -v cn="${codename}" 'NF > 0 && $1 != cn'
    # Preserve the target codename's curated qBittorrent rows (static-binary; generate skips them).
    tail -n +2 "${manifest}" | awk -v cn="${codename}" 'NF > 0 && $1 == cn && $2 == "qbittorrent"'
    cat "${genfile}"
  } | qbcompile::sync::canonical_sort
}

################################################################################
# @description: Reorder the existing packages.lst into canonical order with no
#   pull and no generation — a pure reorder of the rows already present.
#   Writes header + canonical body to stdout.
################################################################################
qbcompile::sync::canonicalize() {
  local manifest="${dest}/packages.lst"
  printf '%s\n' "$(head -n 1 "${manifest}")"
  tail -n +2 "${manifest}" | qbcompile::sync::canonical_sort
}

################################################################################
# @description: Orchestrator.
################################################################################
qbcompile::sync::main() {
  qbcompile::sync::defaults
  qbcompile::sync::parse "$@"

  local manifest="${dest}/packages.lst"
  local rebuilt label
  rebuilt="$(mktemp)"

  if [[ "${canonicalize}" == "true" ]]; then
    label="canonicalize"
    qbcompile::sync::canonicalize >"${rebuilt}"
  else
    label="${codename}"
    qbcompile::sync::pull
    local genfile
    genfile="$(mktemp)"
    qbcompile::sync::generate >"${genfile}"
    qbcompile::sync::rebuild "${genfile}" >"${rebuilt}"
    rm -f "${genfile}"
  fi

  if [[ "${dry_run}" == "true" ]]; then
    printf 'dry-run: diff for %s (no file written)\n' "${label}" >&2
    if diff -u "${manifest}" "${rebuilt}"; then
      printf 'dry-run: no changes\n' >&2
    fi
    rm -f "${rebuilt}"
    return 0
  fi

  mv "${rebuilt}" "${manifest}"
  printf 'wrote %s data rows into %s (%s)\n' \
    "$(awk 'NF > 0' "${manifest}" | tail -n +2 | grep -c .)" "${manifest}" "${label}" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  qbcompile::sync::main "$@"
fi
