#!/bin/bash

BASE=$(dirname $(realpath "${BASH_SOURCE:-$0}"))
echo "Script is located in $BASE"

# heading <text>
function heading() {
  echo "--- $1"
  echo "============================================================="
}

function completed() {
  echo "Done."
  echo "-------------------------------------------------------------"
  echo ""
}

# is_mounted <path>
function is_mounted() {
  [[ ! -z $(mount | grep "\\s$1\\s") ]] && true
}

# file_contains_lines <file-path> <lines>
function file_contains_lines() {
  [[ ! -z $(grep -Pzl "${2//\n/\\n}" "$1") ]] && true
}

# move_and_link_dotted_files <config-dir> <file-name>...
# Moves ".<file-name>" to <config-dir>/<file-name> and creates a symbolic link
# from <config-dir>/.<file-name> to <config-dir>/<file-name>, if ".<file-name>"
# exists.
function move_and_link_dotted_files() {
  local CONFIG_DIR="$1"
  mkdir -p "$CONFIG_DIR"
  shift
  while [ $# -gt 0 ]; do
    if [ -e ".$1" ]; then
      mv ".$1" "$CONFIG_DIR/$1"
      ln -s "$1" "$CONFIG_DIR/.$1"
    fi
    shift
  done
}

# mount_virtiofs <share-name> <mount-path>
# Mounts the virtiofs file system with <share-name> to <mount-path>.
# Outputs the equivalent fstab line when successful.
function mount_virtiofs_share() {
  local SHARE="$1"
  local MOUNT_PATH="$2"
  sudo mkdir -p "$MOUNT_PATH" && \
  sudo mount -t virtiofs "$SHARE" "$MOUNT_PATH" >/dev/null 2>&1 && \
  cat <<END
$SHARE	$MOUNT_PATH	virtiofs	rw,nofail	0	0
END
}

# mount_virtfs <share-name> <mount-path>
# Mounts the virtfs file system with <share-name> to <mount-path>.
# Remounts <mount-path> using bindfs to correct sharing permissions.
# Outputs the equivalent fstab lines when successful.
function mount_virtfs_share() {
  local SHARE="$1"
  local MOUNT_PATH="$2"
  sudo mkdir -p "$MOUNT_PATH" && \
  sudo mount -t 9p -o trans=virtio "$SHARE" "$MOUNT_PATH" -oversion=9p2000.L >/dev/null 2>&1 && (\
    MAPPING="$(stat -c '%u' "$MOUNT_PATH")/$(stat -c '%u' "$HOME"):@$(stat -c '%g' "$MOUNT_PATH")/@$(stat -c '%g' "$HOME")"
    sudo bindfs "--map=$MAPPING" "$MOUNT_PATH" "$MOUNT_PATH" && \
    cat <<END
$SHARE	$MOUNT_PATH	9p	trans=virtio,version=9p2000.L,rw,_netdev,nofail	0	0
$MOUNT_PATH	$MOUNT_PATH	fuse.bindfs	map=$MAPPING	0	0
END
  )
}

# mount_virtiofs_or_virtfs_share <share-name> <virtiofs-mount-path> <virtfs-mount-path>
# Mounts either virtiofs or virtfs file system with <share-name>, if found.
# Outputs the equivalent fstab lines when successful.
function mount_virtiofs_or_virtfs_share() {
  mount_virtiofs_share "$1" "$2" || \
  mount_virtfs_share "$1" "$3"
}

# install_fonts <font-name>...
function install_fonts() {
  local version='3.0.2'
  local fonts_dir="${HOME}/.local/share/fonts"

  mkdir -p "$fonts_dir"
  while [ $# -gt 0 ]; do
    local font="$1"
    local zip_file="${font}.zip"
    local download_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v${version}/${zip_file}"
    wget "$download_url"
    unzip "$zip_file" -d "$fonts_dir" -x "*.txt/*" -x "*.md/*"
    rm "$zip_file"
    shift
  done
  find "$fonts_dir" -name '*Windows Compatible*' -delete

  fc-cache -fv
}


heading "Updating OS"
DEBIAN_FRONTEND=noninteractive sudo apt update && DEBIAN_FRONTEND=noninteractive sudo apt full-upgrade -y
completed

heading "Installing essential tools"
DEBIAN_FRONTEND=noninteractive sudo apt-get install git curl wget grep sed gnupg gpg bindfs build-essential cmake cargo nano micro apt-utils -y
completed

heading "Mounting share (if provided)"
FSTAB_LINES=$(mount_virtiofs_or_virtfs_share share /mnt/share "/mnt/share/$USER")
if [ ! -z "$FSTAB_LINES" ] && ! file_contains_lines /etc/fstab "$FSTAB_LINES"; then
  echo "$FSTAB_LINES" | sudo tee -a /etc/fstab >/dev/null
fi
completed

heading "Setting up initial config"
if [ ! -d ~/.config/zsh ]; then
  cp -R "$BASE/home/." "$HOME/"
fi
completed

heading "Installing asdf"
export ASDF_DIR="$HOME/.local/asdf"
export asdf_dir="$ASDF_DIR"
export ASDF_DATA_DIR="$ASDF_DIR/data"
if [ ! -e "$ASDF_DIR/asdf.sh" ]; then
  sudo apt-get install zlib1g-dev libyaml-dev

  if [ ! -d "$ASDF_DIR" ]; then
    git clone https://github.com/asdf-vm/asdf.git "$ASDF_DIR"
    git -C "$ASDF_DIR" checkout --detach $(git -C "$ASDF_DIR" tag --list | sort -rV | head -n 1)
  fi

  . "$ASDF_DIR/asdf.sh"
  asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git && asdf install nodejs latest && asdf global nodejs latest
  asdf plugin add ruby https://github.com/asdf-vm/asdf-ruby.git && asdf install ruby latest && asdf global ruby latest
  asdf plugin add yarn && asdf install yarn latest && asdf global yarn latest
fi
completed

heading "Installing zsh"
DEBIAN_FRONTEND=noninteractive sudo apt-get install zsh -y

ZSH_PLUGINS_DIR="$HOME/.local/zsh/plugins"
mkdir -p "$ZSH_PLUGINS_DIR"
if [ ! -d "$ZSH_PLUGINS_DIR/asdf" ]; then
  git clone https://github.com/kiurchv/asdf.plugin.zsh.git "$ZSH_PLUGINS_DIR/asdf"
fi
if [ ! -d "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
fi
if [ ! -d "$ZSH_PLUGINS_DIR/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_PLUGINS_DIR/zsh-autosuggestions"
fi
completed

heading "Configure bash"
if [ ! -f "~/.bashrc" ] || ! file_contains_lines "~/.bashrc" ". ~/.config/bash/bashrc"; then
  echo ". ~/.config/bash/bashrc" | tee -a "$HOME/.bashrc" >/dev/null
fi
completed

heading "Installing startship prompt"
cargo install starship --locked
completed

heading "Install docker"
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  CODENAME=$(lsb_release -cs)
  ARCH=$(dpkg --print-architecture)

  DEBIAN_FRONTEND=noninteractive sudo apt-get install ca-certificates -y

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt update
  sudo group add docker
  DEBIAN_FRONTEND=noninteractive sudo apt-get install docker-ce docker-ce-cli -y
  sudo usermod -aG docker ${USER}
fi
completed

heading "Install desktop"
DEBIAN_FRONTEND=noninteractive sudo apt install gdm3 ubuntu-desktop^ -y
completed

heading "Install some nerd fonts"
if [ ! -d ~/.local/share/fonts ]; then
  install_fonts CascadiaCode ComicShannsMono FantasqueSansMono FiraCode Noto OpenDyslexic VictorMono
fi
completed

heading "Install Visual Studio Code"
if [ ! -f /etc/apt/keyrings/packages.microsoft.gpg ]; then
  CODENAME=$(lsb_release -cs)
  ARCH=$(dpkg --print-architecture)

  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
  sudo chmod a+r /etc/apt/keyrings/packages.microsoft.gpg

  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
    sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

  DEBIAN_FRONTEND=noninteractive sudo apt-get install apt-transport-https -y
  sudo apt update
  DEBIAN_FRONTEND=noninteractive sudo apt-get install code -y # or code-insiders
fi
completed

heading "Tips"
echo " - log out and back in to see some changes"
echo " - allow a user to run docker commands: e.g. \`sudo usermod -aG docker \${USER}\`"
echo " - change your default shell: e.g. \`chsh -s $(which zsh)\`"
echo " - set up your SSH keys"
echo " - set up you GPG keys"
completed
