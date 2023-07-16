#!/bin/bash

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


echo "1. Updating OS"
DEBIAN_FRONTEND=noninteractive sudo apt update && DEBIAN_FRONTEND=noninteractive sudo apt full-upgrade -y

echo "2. Installing essential tools"
DEBIAN_FRONTEND=noninteractive sudo apt-get install git curl wget grep sed gnupg gpg bindfs build-essential cargo nano micro apt-utils -y

echo "3. Mounting share (if provided)"
FSTAB_LINES=$(mount_virtiofs_or_virtfs_share share /mnt/share "/mnt/share/$USER")
if [ ! -z "$FSTAB_LINES" ] && ! file_contains_lines /etc/fstab "$FSTAB_LINES"; then
  echo "$FSTAB_LINES" | sudo tee -a /etc/fstab >/dev/null
fi

echo "4. Installing ZSH"
DEBIAN_FRONTEND=noninteractive sudo apt-get install zsh -y

echo "5. Setting up .config and .local"
ZDOTDIR="$HOME/.config/zsh"
ZSH_PLUGINS_DIR="$HOME/.local/zsh/plugins"
mkdir -p "$ZDOTDIR"
mkdir -p "$ZSH_PLUGINS_DIR"
if [ ! -e "$ZDOTDIR/zshrc" ]; then
  move_and_link_dotted_files "$ZDOTDIR" zshenv zprofile zshrc zlogin zlogout
  touch "$ZDOTDIR/zshenv"
  ln -s "zshenv" "$ZDOTDIR./zshenv"
  cat <<"END" >"~/.zshenv"
ZDOTDIR="$HOME/.config/zsh"
. $ZDOTDIR/.zshenv
END
  if [ ! -f "$ZDOTDIR/zshrc" ]; then
    cat <<END >"$ZDOTDIR/zshrc"
autoload -Uz compinit promptinit
compinit
promptinit

# Selected plugins
plugins=()

# Source selected plugins
for index in {1..\$#plugins}; do
  . "$ZSH_PLUGINS_DIR/\$plugins[index]/\$plugins[index].plugin.zsh"
done

# This will set the default prompt to the walters theme
prompt walters
END
  fi
fi

echo "7. Installing startship prompt"
cargo install starship --locked
if file_contains_lines "$ZDOTDIR/zshrc" "eval \"\$(starship init zsh)\""; then
  echo "eval \"\$(starship init zsh)\"" | tee -a "$ZDOTDIR/zshrc" >/dev/null
fi
if file_contains_lines "~/.bashrc" "eval \"\$(starship init bash)\""; then
  echo "eval \"\$(starship init bash)\"" | tee -a "~/.bashrc" >/dev/null
fi

echo "8. Installing asdf"
ASDF_DIR="$HOME/.local/asdf"
asdf_dir="$ASDF_DIR"
if [ ! -e "$ASDF_DIR/asdf.sh" ]; then
  ASDF_CONFIG_FILE="$HOME/config/asdf/asdfrc"
  mkdir -p "$HOME/config/asdf"
  sudo apt install zlib1g-dev libyaml-dev

  echo "ASDF_DIR=\"$ASDF_DIR\"" >>"$ZDOTDIR/zshrc"
  echo "asdf_dir=\"\$ASDF_DIR\"" >>"$ZDOTDIR/zshrc"
  echo "ASDF_CONFIG_FILE=\"$ASDF_CONFIG_FILE\"" >>"$ZDOTDIR/zshrc"
  echo "source \"$ASDF_DIR/asdf.sh\"" >>"$ZDOTDIR/zshrc"
  echo "legacy_version_file = yes" >>"$ASDF_CONFIG_FILE"

  if [ ! -d "$ASDF_DIR" ]; then
    git clone https://github.com/asdf-vm/asdf.git "$ASDF_DIR"
    git -C "$ASDF_DIR" checkout --detach $(git -C "$ASDF_DIR" tag --list | sort -rV | head -n 1)
  fi
  if [ ! -d "$ZSH_PLUGINS_DIR/asdf" ]; then
    git clone https://github.com/kiurchv/asdf.plugin.zsh.git "$ZSH_PLUGINS_DIR/asdf"
  fi
  if ! grep -E "^plugins=\\([^\\)\\r\\n]*\\basdf\\b" "$ZDOTDIR/zshrc" >/dev/null; then
    sed -i -E "s/^(plugins=\\([^\\)\\r\\n]*)/\\1 asdf/" "$ZDOTDIR/zshrc"
    sed -i -E "s/^(plugins=\\()\\s+/\\1/" "$ZDOTDIR/zshrc"
  fi

  zsh -c "asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git && asdf install nodejs latest && asdf global nodejs latest"

  zsh -c "asdf plugin add ruby https://github.com/asdf-vm/asdf-ruby.git && asdf install ruby latest && asdf global ruby latest"

  zsh -c "asdf plugin add yarn && asdf install yarn latest && asdf global yarn latest"
fi
