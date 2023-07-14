#!/bin/bash

function is_mounted() { # is_mounted <path>
  [[ ! -z $(mount | grep "\\s$1\\s") ]] && true
}

function file_contains_lines() { # file_contains_lines <file-path> <lines>
  [[ ! -z $(grep -Pzl "$2" "$1") ]] && true
}

# mount_virtiofs <share-name> <mount-path>
# Mounts the virtiofs file system with <share-name> to <mount-path>.
# Outputs the equivalent fstab line when successful.
function mount_virtiofs_share() {
  local SHARE="$1"
  local MOUNT_PATH="$2"
  sudo mkdir -p "$MOUNT_PATH" && \
  sudo mount -t virtiofs "$SHARE" "$MOUNT_PATH" >/dev/null 2>1 && \
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
  local MAPPING="$(stat -c '%u' "$MOUNT_PATH")/$(stat -c '%u' "$HOME"):@$(stat -c '%g' "$MOUNT_PATH")/@$(stat -c '%g' "$HOME")"
  sudo mkdir -p "$MOUNT_PATH" && \
  sudo mount -t 9p -o trans=virtio "$SHARE" "$MOUNT_PATH" -oversion=9p2000.L >/dev/null 2>1 && \
  sudo bindfs "--map=$MAPPING" "$MOUNT_PATH" "$MOUNT_PATH" && \
  cat <<END
$SHARE	$MOUNT_PATH	9p	trans=virtio,version=9p2000.L,rw,_netdev,nofail	0	0
$MOUNT_PATH	$MOUNT_PATH	fuse.bindfs	map=$MAPPING	0	0
END
}

# mount_virtiofs_or_virtfs_share <share-name> <virtiofs-mount-path> <virtfs-mount-path>
# Mounts either virtiofs or virtfs file system with <share-name>, if found.
# Outputs the equivalent fstab lines when successful.
function mount_virtiofs_or_virtfs_share() {
  mount_virtiofs_share "$1" "$2" || \
  mount_virtfs_share "$1" "$3"
}


echo "1. Updating OS"
DEBIAN_FRONTEND=noninteractive sudo apt update && DEBIAN_FRONTEND=noninteractive sudo apt full-upgrade -y >/dev/null

echo "2. Installing essential tools"
DEBIAN_FRONTEND=noninteractive sudo apt install git curl wget grep sed gnupg gpg bindfs build-essential nano micro -y >/dev/null

echo "3. Mounting share (if provided)"
FSTAB_LINES=$(mount_virtiofs_or_virtfs_share share /mnt/share "/mnt/share/$USER")
if [ ! -z "$FSTAB_LINES" ] && ! file_contains_lines /etc/fstab "$FSTAB_LINES"; then
  echo "$FSTAB_LINES" | sudo tee -a /etc/fstab >/dev/null
fi

echo "4. Installing ZSH"
DEBIAN_FRONTEND=noninteractive sudo apt install zsh -y
