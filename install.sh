#!/usr/bin/env bash
# ============================================================================
# Universal Claude Code Skill Installer
# ============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/anombyte93/claude-session-init/main/install.sh | bash
#   bash install.sh                # fresh install (v2, default)
#   bash install.sh --version v1   # install v1 (monolithic SKILL.md, no script)
#   bash install.sh --version v2   # install v2 (SKILL.md + session-init.py)
#   bash install.sh --revert       # revert from v2 to v1
#   bash install.sh --check-update # check for newer version only
# ============================================================================

set -euo pipefail

REPO_OWNER="anombyte93"
REPO_NAME="claude-session-init"
SKILL_NAME="start"
VERSION="3.0.0"
SKILL_DIR="${SKILL_DIR:-${HOME}/.claude/skills/${SKILL_NAME}}"
TEMPLATE_DIR="${HOME}/claude-session-init-templates"

UPDATES_DIR="${HOME}/.config/claude-skills"
UPDATES_FILE="${UPDATES_DIR}/updates.json"
UPDATE_INTERVAL_SECONDS=86400
GITHUB_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
CLONE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

if [[ -t 1 ]] && [[ -z "${CI:-}" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

info()  { printf "${CYAN}[info]${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}[ok]${RESET}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${RESET}  %s\n" "$*"; }
err()   { printf "${RED}[error]${RESET} %s\n" "$*" >&2; }
die()   { err "$@"; exit 1; }

cleanup() {
    if [[ -n "${TMPDIR_SKILL:-}" ]] && [[ -d "${TMPDIR_SKILL}" ]]; then
        rm -rf "${TMPDIR_SKILL}"
    fi
}
trap cleanup EXIT

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

check_update() {
    if [[ -n "${CI:-}" ]] || [[ -n "${NO_UPDATE_CHECK:-}" ]]; then return 0; fi
    require_cmd curl; require_cmd date; mkdir -p "${UPDATES_DIR}"
    if [[ -f "${UPDATES_FILE}" ]]; then
        local last_check; last_check=$(python3 -c "
import json
try:
    d = json.load(open('${UPDATES_FILE}'))
    print(d.get('skills', {}).get('${SKILL_NAME}', {}).get('last_check', 0))
except: print(0)
" 2>/dev/null || echo 0)
        local now; now=$(date +%s); local elapsed=$(( now - last_check ))
        if [[ ${elapsed} -lt ${UPDATE_INTERVAL_SECONDS} ]]; then
            local cached_latest; cached_latest=$(python3 -c "
import json
try:
    d = json.load(open('${UPDATES_FILE}'))
    print(d.get('skills', {}).get('${SKILL_NAME}', {}).get('latest', ''))
except: print('')
" 2>/dev/null || echo "")
            if [[ -n "${cached_latest}" ]] && [[ "${cached_latest}" != "${VERSION}" ]]; then
                warn "Update available: ${VERSION} -> ${cached_latest}"
                info "Run: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/install.sh | bash"
            fi; return 0
        fi
    fi
    local api_response; api_response=$(curl -fsSL --max-time 5 -H "Accept: application/vnd.github+json" "${GITHUB_API}" 2>/dev/null) || return 0
    local latest_version; latest_version=$(printf '%s' "${api_response}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin); tag = data.get('tag_name', ''); print(tag.lstrip('v'))
except: print('')
" 2>/dev/null || echo "")
    if [[ -z "${latest_version}" ]]; then return 0; fi
    local now; now=$(date +%s)
    python3 -c "
import json
path = '${UPDATES_FILE}'
try: data = json.load(open(path))
except: data = {}
data.setdefault('skills', {})
data['skills']['${SKILL_NAME}'] = {'last_check': ${now}, 'latest': '${latest_version}', 'current': '${VERSION}'}
with open(path, 'w') as f: json.dump(data, f, indent=2)
" 2>/dev/null || true
    if [[ "${latest_version}" != "${VERSION}" ]]; then
        warn "Update available: ${VERSION} -> ${latest_version}"
        info "Run: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/install.sh | bash"
    else ok "You are on the latest version (${VERSION})"; fi
}

revert_to_v1() {
    info "Reverting to v1 (monolithic SKILL.md, no script)"

    if [[ ! -d "${SKILL_DIR}" ]]; then
        die "No installation found at ${SKILL_DIR}. Nothing to revert."
    fi

    TMPDIR_SKILL=$(mktemp -d "${TMPDIR:-/tmp}/claude-skill-XXXXXX")
    info "Cloning ${REPO_OWNER}/${REPO_NAME}..."
    git clone --depth 1 --quiet "${CLONE_URL}" "${TMPDIR_SKILL}/repo" 2>/dev/null \
        || die "Failed to clone repository."

    local src_dir="${TMPDIR_SKILL}/repo"

    if [[ ! -f "${src_dir}/v1/SKILL.md" ]]; then
        die "v1/SKILL.md not found in repository. Cannot revert."
    fi

    # Back up current v2 files
    if [[ -f "${SKILL_DIR}/SKILL.md" ]]; then
        cp "${SKILL_DIR}/SKILL.md" "${SKILL_DIR}/SKILL.md.v2-backup"
        ok "Backed up v2 SKILL.md -> SKILL.md.v2-backup"
    fi
    if [[ -f "${SKILL_DIR}/session-init.py" ]]; then
        cp "${SKILL_DIR}/session-init.py" "${SKILL_DIR}/session-init.py.v2-backup"
        ok "Backed up session-init.py -> session-init.py.v2-backup"
    fi

    # Install v1 SKILL.md
    cp "${src_dir}/v1/SKILL.md" "${SKILL_DIR}/SKILL.md"
    ok "Installed v1 SKILL.md (867 lines, monolithic)"

    # Remove session-init.py (v1 doesn't use it)
    if [[ -f "${SKILL_DIR}/session-init.py" ]]; then
        rm "${SKILL_DIR}/session-init.py"
        ok "Removed session-init.py (not used by v1)"
    fi

    local timestamp; timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    cat > "${SKILL_DIR}/.version" <<VEOF
${VERSION}-v1
installed: ${timestamp}
mode: revert
repo: ${REPO_OWNER}/${REPO_NAME}
skill_version: v1
VEOF
    ok "Wrote .version (${VERSION}-v1, ${timestamp})"

    printf "\n"
    printf "${GREEN}${BOLD}Successfully reverted to v1${RESET}\n"
    printf "  Location: %s\n" "${SKILL_DIR}"
    printf "  Note: v2 files backed up with .v2-backup extension\n"
    printf "\n"
}

install_skill() {
    local target_version="${1:-v2}"
    local mode="install"

    info "Claude Code Skill Installer"
    info "Skill: ${BOLD}${SKILL_NAME}${RESET} v${VERSION} (${target_version})"
    printf "\n"; require_cmd git

    if [[ -d "${SKILL_DIR}" ]]; then
        mode="upgrade"
        local existing_version="unknown"
        if [[ -f "${SKILL_DIR}/.version" ]]; then
            existing_version=$(head -1 "${SKILL_DIR}/.version" 2>/dev/null || echo "unknown")
        fi
        info "Existing installation detected (${existing_version})"
        info "Mode: upgrade"
        if [[ -f "${SKILL_DIR}/SKILL.md" ]]; then
            cp "${SKILL_DIR}/SKILL.md" "${SKILL_DIR}/SKILL.md.bak"
            ok "Backed up SKILL.md -> SKILL.md.bak"
        fi
    else info "Mode: fresh install"; fi

    TMPDIR_SKILL=$(mktemp -d "${TMPDIR:-/tmp}/claude-skill-XXXXXX")
    info "Cloning ${REPO_OWNER}/${REPO_NAME}..."
    git clone --depth 1 --quiet "${CLONE_URL}" "${TMPDIR_SKILL}/repo" 2>/dev/null \
        || die "Failed to clone repository."

    local src_dir="${TMPDIR_SKILL}/repo"

    mkdir -p "${SKILL_DIR}"

    if [[ "${target_version}" == "v1" ]]; then
        # ── v1 install: monolithic SKILL.md, no script ──
        if [[ -f "${src_dir}/v1/SKILL.md" ]]; then
            cp "${src_dir}/v1/SKILL.md" "${SKILL_DIR}/SKILL.md"
            ok "Installed v1 SKILL.md (867 lines, monolithic)"
        else
            die "v1/SKILL.md not found in repository."
        fi
        # Remove session-init.py if present from previous v2 install
        if [[ -f "${SKILL_DIR}/session-init.py" ]]; then
            rm "${SKILL_DIR}/session-init.py"
            ok "Removed session-init.py (not used by v1)"
        fi
    else
        # ── v2 install: slim SKILL.md + session-init.py ──
        # Check for SKILL.md or start.md (legacy)
        if [[ ! -f "${src_dir}/SKILL.md" ]] && [[ -f "${src_dir}/start.md" ]]; then
            cp "${src_dir}/start.md" "${src_dir}/SKILL.md"
        fi
        if [[ ! -f "${src_dir}/SKILL.md" ]]; then
            die "SKILL.md not found in repository."
        fi
        cp "${src_dir}/SKILL.md" "${SKILL_DIR}/SKILL.md"
        ok "Installed v2 SKILL.md (203 lines, orchestrator)"

        # Install session-init.py
        if [[ -f "${src_dir}/session-init.py" ]]; then
            cp "${src_dir}/session-init.py" "${SKILL_DIR}/session-init.py"
            chmod +x "${SKILL_DIR}/session-init.py"
            ok "Installed session-init.py (548 lines, 9 subcommands)"
        else
            die "session-init.py not found in repository. v2 requires this file."
        fi
    fi

    # Install templates (same for both versions)
    if [[ -d "${src_dir}/templates" ]]; then
        mkdir -p "${TEMPLATE_DIR}"
        cp "${src_dir}/templates/"* "${TEMPLATE_DIR}/" 2>/dev/null || true
        ok "Installed templates to ${TEMPLATE_DIR}/"
    fi

    if [[ -f "${src_dir}/install.sh" ]]; then
        cp "${src_dir}/install.sh" "${SKILL_DIR}/install.sh"
        chmod +x "${SKILL_DIR}/install.sh"
    fi

    local timestamp; timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    cat > "${SKILL_DIR}/.version" <<VEOF
${VERSION}
installed: ${timestamp}
mode: ${mode}
repo: ${REPO_OWNER}/${REPO_NAME}
skill_version: ${target_version}
VEOF
    ok "Wrote .version (${VERSION}, ${timestamp})"

    # Clean up old flat file if it exists
    if [[ -f "${HOME}/.claude/skills/start.md" ]]; then
        rm "${HOME}/.claude/skills/start.md"
        ok "Removed old flat file start.md"
    fi

    printf "\n"
    printf "${GREEN}${BOLD}Successfully %s ${SKILL_NAME} v${VERSION} (${target_version})${RESET}\n" \
        "$([ "${mode}" = "upgrade" ] && echo "upgraded" || echo "installed")"
    printf "  Location: %s\n" "${SKILL_DIR}"
    printf "  Templates: %s\n" "${TEMPLATE_DIR}"
    if [[ "${target_version}" == "v2" ]]; then
        printf "  Script: %s/session-init.py\n" "${SKILL_DIR}"
    fi
    printf "\n"
    info "To use this skill in Claude Code:"
    printf "  ${CYAN}/start${RESET}\n"
    printf "\n"
}

main() {
    local target_version="v2"

    case "${1:-}" in
        --check-update|-u) check_update ;;
        -v) echo "${SKILL_NAME} v${VERSION}" ;;
        --revert) revert_to_v1 ;;
        --help|-h)
            printf "Usage: %s [OPTIONS]\n" "${0##*/}"
            printf "\nOptions:\n"
            printf "  (no args)          Install or upgrade (v2, default)\n"
            printf "  --version v1|v2    Install specific version\n"
            printf "  --revert           Revert from v2 to v1\n"
            printf "  --check-update     Check for newer release\n"
            printf "  -v                 Print version\n"
            printf "  --help             Show help\n"
            printf "\nVersions:\n"
            printf "  v1  Monolithic SKILL.md (867 lines). All logic in markdown.\n"
            printf "  v2  Slim SKILL.md (203 lines) + session-init.py (548 lines).\n"
            printf "      Script handles deterministic ops. SKILL.md handles AI judgment.\n" ;;
        "")
            install_skill "v2"
            check_update ;;
        --version)
            # --version with argument (v1 or v2)
            target_version="${2:-v2}"
            if [[ "${target_version}" != "v1" ]] && [[ "${target_version}" != "v2" ]]; then
                die "Invalid version: ${target_version}. Use v1 or v2."
            fi
            install_skill "${target_version}"
            check_update ;;
        *)
            die "Unknown argument: $1 (try --help)" ;;
    esac
}

main "$@"
