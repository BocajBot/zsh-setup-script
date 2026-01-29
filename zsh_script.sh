#!/bin/sh

# Try to auto-install dependencies via common package managers.
install_deps() {
    os_name="$(uname -s 2>/dev/null || echo unknown)"
    is_linux=0
    if [ "$os_name" = "Linux" ]; then
        is_linux=1
    fi

    if [ "$is_linux" -eq 1 ]; then
        if command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y curl git zsh
            return $?
        fi
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y curl git zsh
            return $?
        fi
        if command -v pacman >/dev/null 2>&1; then
            sudo pacman -Syu --noconfirm curl git zsh
            return $?
        fi
        if command -v yay >/dev/null 2>&1; then
            yay -Syu --noconfirm curl git zsh
            return $?
        fi
        if command -v paru >/dev/null 2>&1; then
            paru -Syu --noconfirm curl git zsh
            return $?
        fi
        if command -v brew >/dev/null 2>&1; then
            brew install curl git zsh
            return $?
        fi
        return 1
    fi

    if command -v brew >/dev/null 2>&1; then
        brew install curl git zsh
        return $?
    fi
    return 1
}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        missing=1
    fi
}

STATE_FILE="$HOME/.codex_zsh_setup_state"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
had_zshrc=0
if [ -f "$ZSHRC" ]; then
    had_zshrc=1
fi

if [ "${1:-}" = "--uninstall" ]; then
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE"
    fi

    if [ -f "$ZSHRC.codex-zsh-setup.bak" ]; then
        mv "$ZSHRC.codex-zsh-setup.bak" "$ZSHRC"
    fi

    if [ "${INSTALLED_ZSH_SYNTAX_HIGHLIGHTING:-0}" = "1" ]; then
        rm -rf "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
    fi
    if [ "${INSTALLED_ZSH_AUTOSUGGESTIONS:-0}" = "1" ]; then
        rm -rf "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
    fi
    if [ "${INSTALLED_HISTORY_SUBSTRING_SEARCH:-0}" = "1" ]; then
        rm -rf "$ZSH_CUSTOM_DIR/plugins/history-substring-search"
    fi

    if [ "${INSTALLED_OHMYZSH:-0}" = "1" ]; then
        rm -rf "$HOME/.oh-my-zsh"
    fi

    if command -v chsh >/dev/null 2>&1; then
        if [ -n "${ORIGINAL_SHELL:-}" ]; then
            chsh -s "$ORIGINAL_SHELL"
        else
            printf '%s\n' "Original shell not recorded; please change your login shell manually."
        fi
    else
        printf '%s\n' "chsh not found; please change your login shell manually."
    fi

    rm -f "$STATE_FILE"
    printf '%s\n' "Uninstall complete."
    exit 0
fi

missing=0
need_cmd curl
need_cmd git
need_cmd zsh

original_shell=""
if command -v getent >/dev/null 2>&1; then
    original_shell="$(getent passwd "$USER" | cut -d: -f7)"
fi
if [ -z "$original_shell" ]; then
    original_shell="${SHELL:-}"
fi

if [ "$missing" -ne 0 ]; then
    printf '%s\n' "Attempting to install missing dependencies (curl, git, zsh)..."
    if ! install_deps; then
        printf '%s\n' "No supported package manager found. Please install curl, git, and zsh manually."
        exit 1
    fi
fi

# Backup existing .zshrc before Oh My Zsh can modify it.
if [ "$had_zshrc" -eq 1 ] && [ ! -f "$ZSHRC.codex-zsh-setup.bak" ]; then
    cp "$ZSHRC" "$ZSHRC.codex-zsh-setup.bak"
fi

# Install Oh My Zsh
installed_ohmyzsh=0
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    installed_ohmyzsh=1
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Clone plugins that require downloads

clone_plugin() {
    repo="$1"
    name="$2"
    target="$ZSH_CUSTOM_DIR/plugins/$name"
    if [ ! -d "$target" ]; then
        git clone "$repo" "$target"
    fi
}

INSTALLED_ZSH_SYNTAX_HIGHLIGHTING=0
INSTALLED_ZSH_AUTOSUGGESTIONS=0
INSTALLED_HISTORY_SUBSTRING_SEARCH=0

if [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]; then
    clone_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git" "zsh-syntax-highlighting"
    if [ -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]; then
        INSTALLED_ZSH_SYNTAX_HIGHLIGHTING=1
    fi
fi
if [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]; then
    clone_plugin "https://github.com/zsh-users/zsh-autosuggestions.git" "zsh-autosuggestions"
    if [ -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]; then
        INSTALLED_ZSH_AUTOSUGGESTIONS=1
    fi
fi
if [ ! -d "$ZSH_CUSTOM_DIR/plugins/history-substring-search" ]; then
    clone_plugin "https://github.com/zsh-users/zsh-history-substring-search.git" "history-substring-search"
    if [ -d "$ZSH_CUSTOM_DIR/plugins/history-substring-search" ]; then
        INSTALLED_HISTORY_SUBSTRING_SEARCH=1
    fi
fi

# Add plugins to .zshrc (portable, no in-place sed)
if [ -f "$ZSHRC" ]; then
    source_rc="$ZSHRC"
    if [ "$had_zshrc" -eq 1 ] && [ ! -f "$ZSHRC.codex-zsh-setup.bak" ]; then
        cp "$ZSHRC" "$ZSHRC.codex-zsh-setup.bak"
        source_rc="$ZSHRC.codex-zsh-setup.bak"
    fi
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX")" || exit 1
    awk '
        function has_plugin(name, n, i) {
            for (i = 1; i <= n; i++) {
                if (plugins[i] == name) {
                    return 1
                }
            }
            return 0
        }
        BEGIN { replaced=0 }
        /^[[:space:]]*plugins=\(/ {
            line=$0
            sub(/^[[:space:]]*plugins=\(/, "", line)
            sub(/\).*/, "", line)
            n=split(line, plugins, /[[:space:]]+/)
            req_count=split("git zsh-syntax-highlighting zsh-autosuggestions history-substring-search colored-man-pages command-not-found sudo fzf", req, /[[:space:]]+/)
            out=""
            for (i=1; i<=n; i++) {
                if (plugins[i] != "" && !has_plugin(plugins[i], i-1)) {
                    out = (out == "" ? plugins[i] : out " " plugins[i])
                }
            }
            for (i=1; i<=req_count; i++) {
                if (!has_plugin(req[i], n)) {
                    out = (out == "" ? req[i] : out " " req[i])
                }
            }
            print "plugins=(" out ")"
            replaced=1
            next
        }
        { print }
        END {
            if (replaced == 0) {
                print ""
                print "plugins=(git zsh-syntax-highlighting zsh-autosuggestions history-substring-search colored-man-pages command-not-found sudo fzf)"
            }
        }
    ' "$source_rc" > "$tmpfile" && mv "$tmpfile" "$ZSHRC"
else
    printf '%s\n' "No .zshrc found at $ZSHRC; please add plugins manually."
fi

{
    printf '%s\n' "INSTALLED_OHMYZSH=$installed_ohmyzsh"
    printf '%s\n' "INSTALLED_ZSH_SYNTAX_HIGHLIGHTING=$INSTALLED_ZSH_SYNTAX_HIGHLIGHTING"
    printf '%s\n' "INSTALLED_ZSH_AUTOSUGGESTIONS=$INSTALLED_ZSH_AUTOSUGGESTIONS"
    printf '%s\n' "INSTALLED_HISTORY_SUBSTRING_SEARCH=$INSTALLED_HISTORY_SUBSTRING_SEARCH"
    printf '%s\n' "ORIGINAL_SHELL=$original_shell"
} > "$STATE_FILE"

printf '%s\n' "Done. Restart your shell or run: exec zsh"
