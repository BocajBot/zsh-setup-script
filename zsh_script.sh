#!/bin/bash

# Install dependencies
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    sudo apt update && sudo apt install -y curl git zsh
elif [ -f /etc/arch-release ]; then
    # Arch Linux
    sudo pacman -Syu --noconfirm curl git zsh
elif [ -f /etc/fedora-release ]; then
    # Fedora
    sudo dnf install -y curl git zsh
else
    echo "Unsupported distribution. Please install curl, git, and zsh manually."
    exit 1
fi

# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Clone zsh-syntax-highlighting and zsh-autosuggestions plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# Add plugins to .zshrc
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

# Source .zshrc to apply changes
source ~/.zshrc

