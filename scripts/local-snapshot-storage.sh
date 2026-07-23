#!/usr/bin/env bash

quota_glance_prepare_snapshot_directory() {
  local directory="$1"
  local owner_id

  if [[ -L "$directory" ]]; then
    echo "Refusing symlink snapshot directory: $directory" >&2
    return 1
  fi

  if [[ -e "$directory" ]]; then
    if [[ ! -d "$directory" ]]; then
      echo "Snapshot path is not a directory: $directory" >&2
      return 1
    fi
  else
    /bin/mkdir -m 700 "$directory"
  fi

  if [[ -L "$directory" || ! -d "$directory" ]]; then
    echo "Snapshot directory changed during validation: $directory" >&2
    return 1
  fi

  owner_id="$(/usr/bin/stat -f '%u' "$directory")"
  if [[ "$owner_id" != "$EUID" ]]; then
    echo "Snapshot directory is not owned by the current user: $directory" >&2
    return 1
  fi

  /bin/chmod 700 "$directory"
}

quota_glance_migrate_snapshot_if_needed() {
  local legacy_snapshot="$1"
  local local_snapshot="$2"
  local snapshot_directory
  local temporary_snapshot

  if [[ -L "$local_snapshot" ]]; then
    echo "Refusing symlink snapshot destination: $local_snapshot" >&2
    return 1
  fi
  if [[ -e "$local_snapshot" ]]; then
    if [[ -f "$local_snapshot" ]]; then
      return 0
    fi
    echo "Snapshot destination is not a regular file: $local_snapshot" >&2
    return 1
  fi

  if [[ ! -e "$legacy_snapshot" ]]; then
    return 0
  fi
  if [[ -L "$legacy_snapshot" || ! -f "$legacy_snapshot" ]]; then
    echo "Legacy snapshot is not a regular file: $legacy_snapshot" >&2
    return 1
  fi

  snapshot_directory="$(/usr/bin/dirname "$local_snapshot")"
  quota_glance_prepare_snapshot_directory "$snapshot_directory"
  temporary_snapshot="$(mktemp "$snapshot_directory/.snapshot-migration.XXXXXX")"

  if ! /usr/bin/ditto "$legacy_snapshot" "$temporary_snapshot"; then
    /bin/rm -f "$temporary_snapshot"
    echo "Could not copy the legacy snapshot" >&2
    return 1
  fi
  /bin/chmod 600 "$temporary_snapshot"

  if /bin/ln "$temporary_snapshot" "$local_snapshot" 2>/dev/null; then
    /bin/rm -f "$temporary_snapshot"
    echo "Migrated shared snapshot to: $local_snapshot"
    return 0
  fi

  /bin/rm -f "$temporary_snapshot"
  if [[ ! -L "$local_snapshot" && -f "$local_snapshot" ]]; then
    return 0
  fi

  echo "Snapshot destination changed during migration: $local_snapshot" >&2
  return 1
}
