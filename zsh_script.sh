#!/bin/bash
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting 
git clone https://github.com/zsh-users/zsh-autosuggestions.git $ZSH_CUSTOM/plugins/zsh-autosuggestions 
sed -i 's/(git)/(git zsh-autosuggestions zsh-syntax-highlighting)/g' ~/.zshrc 
source ~/.zshrc
