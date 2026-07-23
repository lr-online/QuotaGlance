#!/usr/bin/env bash

quota_glance_require_true_entitlement() {
  local plist="$1"
  local key_path="$2"
  local value

  value="$(
    /usr/bin/plutil -extract "$key_path" raw -expect bool -o - "$plist" \
      2>/dev/null
  )" || return 1
  [[ "$value" == "true" ]]
}

quota_glance_require_single_path_entitlement() {
  local plist="$1"
  local key_path="$2"
  local expected_path="$3"
  local count
  local actual_path

  count="$(
    /usr/bin/plutil -extract "$key_path" raw -expect array -o - "$plist" \
      2>/dev/null
  )" || return 1
  [[ "$count" == "1" ]] || return 1

  actual_path="$(
    /usr/bin/plutil -extract "$key_path.0" raw -expect string -o - "$plist" \
      2>/dev/null
  )" || return 1
  [[ "$actual_path" == "$expected_path" ]]
}

quota_glance_require_absent_entitlement() {
  local plist="$1"
  local key_path="$2"

  ! /usr/bin/plutil -extract "$key_path" raw -o /dev/null "$plist" \
    >/dev/null 2>&1
}

quota_glance_validate_local_entitlements() {
  local app_entitlements="$1"
  local widget_entitlements="$2"
  local shared_directory="$3"
  local sandbox_key='com\.apple\.security\.app-sandbox'
  local network_key='com\.apple\.security\.network\.client'
  local app_group_key='com\.apple\.security\.application-groups'
  local read_only_key=
  local read_write_key=

  read_only_key='com\.apple\.security\.temporary-exception\.files\.absolute-path\.read-only'
  read_write_key='com\.apple\.security\.temporary-exception\.files\.absolute-path\.read-write'

  quota_glance_require_true_entitlement "$app_entitlements" "$sandbox_key" \
    || return 1
  quota_glance_require_true_entitlement "$app_entitlements" "$network_key" \
    || return 1
  quota_glance_require_single_path_entitlement \
    "$app_entitlements" "$read_write_key" "$shared_directory" \
    || return 1
  quota_glance_require_absent_entitlement "$app_entitlements" "$read_only_key" \
    || return 1
  quota_glance_require_absent_entitlement "$app_entitlements" "$app_group_key" \
    || return 1

  quota_glance_require_true_entitlement "$widget_entitlements" "$sandbox_key" \
    || return 1
  quota_glance_require_single_path_entitlement \
    "$widget_entitlements" "$read_only_key" "$shared_directory" \
    || return 1
  quota_glance_require_absent_entitlement \
    "$widget_entitlements" "$read_write_key" \
    || return 1
  quota_glance_require_absent_entitlement \
    "$widget_entitlements" "$app_group_key" \
    || return 1
}
