#!/usr/bin/env bash

quota_glance_validate_source_items() {
  local source_items="$1"
  local expected_prefix="$2"
  local entry
  local normalized_entry
  local component
  local -a components

  [[ -n "$source_items" && -n "$expected_prefix" ]] || return 1

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" != /* \
      && "$entry" != *$'\r'* \
      && "$entry" != *'//'* \
      && "$entry" != './'* \
      && "$entry" != *'/./'* \
      && "$entry" != *'/.' ]] || return 1

    IFS='/' read -r -a components <<< "$entry"
    [[ "${components[0]:-}" == "$expected_prefix" ]] || return 1
    for component in "${components[@]}"; do
      [[ "$component" != '..' ]] || return 1
    done

    normalized_entry="$(
      printf '%s' "$entry" | /usr/bin/tr '[:upper:]' '[:lower:]'
    )"
    if [[ "$normalized_entry" =~ (^|/)\.env($|[./]) \
      || "$normalized_entry" =~ (^|/)\.git(/|$) \
      || "$normalized_entry" =~ (^|/)(deriveddata|dist|\.build|xcuserdata)(/|$) \
      || "$normalized_entry" =~ (^|/)logs?(/|$) \
      || "$normalized_entry" =~ \.log$ \
      || "$normalized_entry" =~ (^|/)snapshots?(/|$) \
      || "$normalized_entry" =~ (^|/)[^/]*snapshot[^/]*\.(json|plist|archive)$ \
      || "$normalized_entry" =~ (^|/)library/preferences(/|$) \
      || "$normalized_entry" =~ (^|/)[^/]*(preferences-export|userdefaults)[^/]*($|/) \
      || "$normalized_entry" =~ \.(keychain|keychain-db|p12|pfx)$ ]]; then
      return 1
    fi
  done <<< "$source_items"
}

quota_glance_validate_mounted_payload() {
  local mount_point="$1"
  local item

  [[ -d "$mount_point/QuotaGlance.app" \
    && ! -L "$mount_point/QuotaGlance.app" ]] || return 1
  for item in README.txt; do
    [[ -f "$mount_point/$item" && ! -L "$mount_point/$item" ]] || return 1
  done
  [[ -L "$mount_point/Applications" \
    && "$(/usr/bin/readlink "$mount_point/Applications")" == "/Applications" ]] \
    || return 1
  [[ -z "$(
    /usr/bin/find "$mount_point/QuotaGlance.app" -type l -print -quit
  )" ]] || return 1
}

quota_glance_validate_gatekeeper_rejection() {
  local status="$1"
  local output="$2"

  [[ "$status" == 3 && "$output" == *': rejected'* ]]
}

quota_glance_mount_info() {
  local attach_plist="$1"
  local device_node=""
  local mount_point=""
  local candidate
  local index=0

  while /usr/libexec/PlistBuddy \
    -c "Print :system-entities:$index" \
    "$attach_plist" >/dev/null 2>&1; do
    if [[ -z "$device_node" ]]; then
      device_node="$(/usr/libexec/PlistBuddy \
        -c "Print :system-entities:$index:dev-entry" \
        "$attach_plist" 2>/dev/null || true)"
    fi
    candidate="$(/usr/libexec/PlistBuddy \
      -c "Print :system-entities:$index:mount-point" \
      "$attach_plist" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      mount_point="$candidate"
      break
    fi
    index=$((index + 1))
  done

  [[ -n "$mount_point" ]] || return 1
  printf '%s\n%s\n' "$device_node" "$mount_point"
}
