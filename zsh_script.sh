#!/usr/bin/env sh
set -eu

STATE_FILE="${HOME}/.zsh_setup_state"
ZSH_DIR="${ZSH:-${HOME}/.oh-my-zsh}"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-${ZSH_DIR}/custom}"
ZSHRC="${ZDOTDIR:-${HOME}}/.zshrc"
BACKUP_ZSHRC="${ZSHRC}.pre-zsh-setup.bak"

CORE_PLUGINS="git sudo colored-man-pages history-substring-search zsh-autosuggestions zsh-syntax-highlighting"
OPTIONAL_PLUGIN_FZF="fzf"
OPTIONAL_PLUGIN_CMD_NOT_FOUND="command-not-found"

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

have() {
    command -v "$1" >/dev/null 2>&1
}

os_name() {
    uname -s 2>/dev/null || printf 'unknown\n'
}

pkg_manager() {
    if have brew; then printf 'brew\n'; return; fi
    if have nala; then printf 'nala\n'; return; fi
    if have apt-get; then printf 'apt-get\n'; return; fi
    if have dnf; then printf 'dnf\n'; return; fi
    if have pacman; then printf 'pacman\n'; return; fi
    if have zypper; then printf 'zypper\n'; return; fi
    if have apk; then printf 'apk\n'; return; fi
    printf 'unknown\n'
}

install_packages() {
    pm="$(pkg_manager)"
    case "$pm" in
        brew)
            brew install git curl zsh fzf
            ;;
        nala)
            sudo nala update
            sudo nala install -y git curl zsh fzf
            ;;
        apt-get)
            sudo apt-get update
            sudo apt-get install -y git curl zsh fzf
            ;;
        dnf)
            sudo dnf install -y git curl zsh fzf
            ;;
        pacman)
            sudo pacman -Syu --noconfirm git curl zsh fzf
            ;;
        zypper)
            sudo zypper refresh
            sudo zypper install -y git curl zsh fzf
            ;;
        apk)
            sudo apk add git curl zsh fzf
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_dependencies() {
    missing=0
    for cmd in git curl zsh; do
        if ! have "$cmd"; then
            missing=1
        fi
    done

    if [ "$missing" -eq 1 ] || ! have fzf; then
        log "Installing required packages and optional fzf support..."
        if ! install_packages; then
            warn "No supported package manager found. Install git, curl, and zsh manually."
            exit 1
        fi
    fi
}

get_shell_path() {
    if have zsh; then
        command -v zsh
        return
    fi

    for p in /bin/zsh /usr/bin/zsh /usr/local/bin/zsh /opt/homebrew/bin/zsh; do
        if [ -x "$p" ]; then
            printf '%s\n' "$p"
            return
        fi
    done

    return 1
}

current_login_shell() {
    if have getent && [ -n "${USER:-}" ]; then
        getent passwd "$USER" | awk -F: '{print $7}'
        return
    fi

    if [ "$(os_name)" = "Darwin" ] && [ -n "${USER:-}" ]; then
        dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
        return
    fi

    printf '%s\n' "${SHELL:-}"
}

shell_in_etc_shells() {
    shell_path="$1"
    [ -r /etc/shells ] || return 1
    grep -Fx "$shell_path" /etc/shells >/dev/null 2>&1
}

set_login_shell_if_safe() {
    target_shell="$1"
    original_shell="$2"

    [ -n "$target_shell" ] || return 0
    [ "$original_shell" = "$target_shell" ] && return 0

    if ! have chsh; then
        warn "chsh is not available. Leaving login shell unchanged."
        return 0
    fi

    if ! shell_in_etc_shells "$target_shell"; then
        warn "$target_shell is not listed in /etc/shells. Leaving login shell unchanged."
        return 0
    fi

    if chsh -s "$target_shell"; then
        log "Login shell changed to $target_shell"
    else
        warn "Unable to change login shell automatically."
    fi
}

backup_zshrc_once() {
    if [ -f "$ZSHRC" ] && [ ! -f "$BACKUP_ZSHRC" ]; then
        cp "$ZSHRC" "$BACKUP_ZSHRC"
    fi
}

install_oh_my_zsh() {
    installed_ohmyzsh=0
    if [ ! -d "$ZSH_DIR" ]; then
        installed_ohmyzsh=1
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    printf '%s\n' "$installed_ohmyzsh"
}

clone_plugin() {
    repo="$1"
    name="$2"
    target="${ZSH_CUSTOM_DIR}/plugins/${name}"

    if [ ! -d "$target" ]; then
        git clone --depth=1 "$repo" "$target"
        return 0
    fi
    return 1
}

install_custom_plugins() {
    installed_zsh_syntax_highlighting=0
    installed_zsh_autosuggestions=0
    installed_history_substring_search=0

    if clone_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git" "zsh-syntax-highlighting"; then
        installed_zsh_syntax_highlighting=1
    fi
    if clone_plugin "https://github.com/zsh-users/zsh-autosuggestions.git" "zsh-autosuggestions"; then
        installed_zsh_autosuggestions=1
    fi
    if clone_plugin "https://github.com/zsh-users/zsh-history-substring-search.git" "history-substring-search"; then
        installed_history_substring_search=1
    fi

    printf '%s:%s:%s\n' \
        "$installed_zsh_syntax_highlighting" \
        "$installed_zsh_autosuggestions" \
        "$installed_history_substring_search"
}

build_plugin_list() {
    plugins="$CORE_PLUGINS"

    if have fzf; then
        plugins="$plugins $OPTIONAL_PLUGIN_FZF"
    fi

    case "$(pkg_manager)" in
        nala|apt-get)
            plugins="$plugins $OPTIONAL_PLUGIN_CMD_NOT_FOUND"
            ;;
    esac

    printf '%s\n' "$plugins"
}

create_base_zshrc_if_missing() {
    if [ ! -f "$ZSHRC" ]; then
        cat > "$ZSHRC" <<EOF2
export ZSH="${ZSH_DIR}"
ZSH_THEME="robbyrussell"
plugins=()
source "${ZSH_DIR}/oh-my-zsh.sh"
EOF2
    fi
}

rewrite_plugins_line() {
    desired_plugins="$1"
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX")"

    awk -v desired_plugins="$desired_plugins" '
        BEGIN { replaced=0 }
        /^[[:space:]]*plugins=\(/ {
            print "plugins=(" desired_plugins ")"
            replaced=1
            next
        }
        { print }
        END {
            if (replaced == 0) {
                print ""
                print "plugins=(" desired_plugins ")"
            }
        }
    ' "$ZSHRC" > "$tmpfile"

    mv "$tmpfile" "$ZSHRC"
}

ensure_line_once() {
    line="$1"
    if ! grep -Fqx "$line" "$ZSHRC" 2>/dev/null; then
        printf '%s\n' "$line" >> "$ZSHRC"
    fi
}

setup_fzf_shell_integration() {
    if ! have fzf; then
        return 0
    fi

    if have brew; then
        fzf_prefix="$(brew --prefix 2>/dev/null)/opt/fzf"
        if [ -f "$fzf_prefix/shell/completion.zsh" ]; then
            ensure_line_once "[ -f \"$fzf_prefix/shell/completion.zsh\" ] && source \"$fzf_prefix/shell/completion.zsh\""
        fi
        if [ -f "$fzf_prefix/shell/key-bindings.zsh" ]; then
            ensure_line_once "[ -f \"$fzf_prefix/shell/key-bindings.zsh\" ] && source \"$fzf_prefix/shell/key-bindings.zsh\""
        fi
        return 0
    fi

    for base in /usr/share/fzf /usr/share/doc/fzf/examples /usr/share/fzf-shell /usr/local/opt/fzf/shell; do
        if [ -f "$base/completion.zsh" ]; then
            ensure_line_once "[ -f \"$base/completion.zsh\" ] && source \"$base/completion.zsh\""
            break
        fi
    done

    for base in /usr/share/fzf /usr/share/doc/fzf/examples /usr/share/fzf-shell /usr/local/opt/fzf/shell; do
        if [ -f "$base/key-bindings.zsh" ]; then
            ensure_line_once "[ -f \"$base/key-bindings.zsh\" ] && source \"$base/key-bindings.zsh\""
            break
        fi
    done
}

write_state() {
    installed_ohmyzsh="$1"
    installed_zsh_syntax_highlighting="$2"
    installed_zsh_autosuggestions="$3"
    installed_history_substring_search="$4"
    original_shell="$5"

    cat > "$STATE_FILE" <<EOF2
INSTALLED_OHMYZSH=$installed_ohmyzsh
INSTALLED_ZSH_SYNTAX_HIGHLIGHTING=$installed_zsh_syntax_highlighting
INSTALLED_ZSH_AUTOSUGGESTIONS=$installed_zsh_autosuggestions
INSTALLED_HISTORY_SUBSTRING_SEARCH=$installed_history_substring_search
ORIGINAL_SHELL=$original_shell
EOF2
}

uninstall_setup() {
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE"
    fi

    if [ -f "$BACKUP_ZSHRC" ]; then
        mv "$BACKUP_ZSHRC" "$ZSHRC"
    fi

    [ "${INSTALLED_ZSH_SYNTAX_HIGHLIGHTING:-0}" = "1" ] && rm -rf "${ZSH_CUSTOM_DIR}/plugins/zsh-syntax-highlighting"
    [ "${INSTALLED_ZSH_AUTOSUGGESTIONS:-0}" = "1" ] && rm -rf "${ZSH_CUSTOM_DIR}/plugins/zsh-autosuggestions"
    [ "${INSTALLED_HISTORY_SUBSTRING_SEARCH:-0}" = "1" ] && rm -rf "${ZSH_CUSTOM_DIR}/plugins/history-substring-search"
    [ "${INSTALLED_OHMYZSH:-0}" = "1" ] && rm -rf "$ZSH_DIR"

    if [ -n "${ORIGINAL_SHELL:-}" ] && have chsh && shell_in_etc_shells "$ORIGINAL_SHELL"; then
        chsh -s "$ORIGINAL_SHELL" || warn "Failed to restore original login shell automatically."
    fi

    rm -f "$STATE_FILE"
    log "Uninstall complete."
}

main() {
    if [ "${1:-}" = "--uninstall" ]; then
        uninstall_setup
        exit 0
    fi

    ensure_dependencies

    original_shell="$(current_login_shell)"
    target_shell="$(get_shell_path || true)"

    backup_zshrc_once
    create_base_zshrc_if_missing

    installed_ohmyzsh="$(install_oh_my_zsh)"

    plugin_flags="$(install_custom_plugins)"
    installed_zsh_syntax_highlighting="$(printf '%s' "$plugin_flags" | cut -d: -f1)"
    installed_zsh_autosuggestions="$(printf '%s' "$plugin_flags" | cut -d: -f2)"
    installed_history_substring_search="$(printf '%s' "$plugin_flags" | cut -d: -f3)"

    desired_plugins="$(build_plugin_list)"
    rewrite_plugins_line "$desired_plugins"
    setup_fzf_shell_integration
    set_login_shell_if_safe "$target_shell" "$original_shell"

    write_state \
        "$installed_ohmyzsh" \
        "$installed_zsh_syntax_highlighting" \
        "$installed_zsh_autosuggestions" \
        "$installed_history_substring_search" \
        "$original_shell"

    log "Done. Restart your shell or run: exec zsh"
}

main "$@"

