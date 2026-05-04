#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/ClashX.xcworkspace"
WORKSPACE_DATA="$WORKSPACE_DIR/contents.xcworkspacedata"
PROJECT_DIR="$ROOT_DIR/ClashX.xcodeproj"
PODS_PROJECT_DIR="$ROOT_DIR/Pods/Pods.xcodeproj"

repair_mode="${SMARTX_ENSURE_WORKSPACE_REPAIR:-0}"
regenerate_mode="${SMARTX_REGENERATE_WORKSPACE:-0}"
regenerate_lock="${SMARTX_REGENERATE_PODFILE_LOCK:-0}"

print_missing_products_hint() {
  echo "CocoaPods workspace products are missing. Run:"
  echo "  bundle install"
  echo "  bundle exec pod install"
}

run_bundler_install_if_needed() {
  if [ ! -f "$ROOT_DIR/Gemfile" ]; then
    echo "Repair failed: Gemfile is missing, so Bundler-managed CocoaPods cannot run."
    return 1
  fi

  if bundle check >/dev/null 2>&1; then
    return 0
  fi

  bundle install
}

run_pod_install() {
  if [ -f "$ROOT_DIR/Gemfile" ]; then
    run_bundler_install_if_needed || return 1
    bundle exec pod install
  else
    pod install
  fi
}

validate_workspace() {
  local locations
  local file_ref_count
  local has_project_ref
  local has_pods_ref

  if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "Workspace is missing: ClashX.xcworkspace"
    return 1
  fi

  if [ ! -s "$WORKSPACE_DATA" ]; then
    echo "Workspace contents file is missing or empty: ClashX.xcworkspace/contents.xcworkspacedata"
    return 1
  fi

  if ! ruby -rrexml/document -e '
      path = ARGV.fetch(0)
      doc = REXML::Document.new(File.read(path))
      root = doc.root
      abort("XML root tag is not Workspace") unless root && root.name == "Workspace"
      refs = REXML::XPath.match(doc, "//FileRef")
      abort("Workspace does not contain any FileRef entries") if refs.empty?
      puts refs.map { |ref| ref.attributes["location"] }.compact
    ' "$WORKSPACE_DATA" > /tmp/smartx-workspace-filerefs.$$ 2>/tmp/smartx-workspace-error.$$; then
    cat /tmp/smartx-workspace-error.$$ 2>/dev/null
    rm -f /tmp/smartx-workspace-filerefs.$$ /tmp/smartx-workspace-error.$$
    return 1
  fi

  locations="$(cat /tmp/smartx-workspace-filerefs.$$ 2>/dev/null)"
  rm -f /tmp/smartx-workspace-filerefs.$$ /tmp/smartx-workspace-error.$$

  file_ref_count="$(printf '%s\n' "$locations" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "${file_ref_count:-0}" -lt 1 ]; then
    echo "Workspace does not contain any FileRef entries"
    return 1
  fi

  has_project_ref=0
  has_pods_ref=0
  while IFS= read -r location; do
    [ -z "$location" ] && continue
    case "$location" in
      group:ClashX.xcodeproj)
        has_project_ref=1
        if [ ! -d "$PROJECT_DIR" ]; then
          echo "Workspace references group:ClashX.xcodeproj, but ClashX.xcodeproj is missing."
          return 1
        fi
        ;;
      group:Pods/Pods.xcodeproj)
        has_pods_ref=1
        if [ ! -d "$PODS_PROJECT_DIR" ]; then
          print_missing_products_hint
          return 1
        fi
        ;;
    esac
  done <<EOF
$locations
EOF

  if [ "$has_project_ref" -ne 1 ]; then
    echo "Workspace does not reference group:ClashX.xcodeproj"
    return 1
  fi

  if [ "$has_pods_ref" -eq 1 ] && [ ! -d "$PODS_PROJECT_DIR" ]; then
    print_missing_products_hint
    return 1
  fi

  if ! xcodebuild -list -workspace "$WORKSPACE_DIR" >/tmp/smartx-workspace-xcodebuild.$$ 2>&1; then
    echo "Workspace XML is valid, but xcodebuild could not resolve ClashX.xcworkspace."
    cat /tmp/smartx-workspace-xcodebuild.$$ 2>/dev/null
    rm -f /tmp/smartx-workspace-xcodebuild.$$
    return 1
  fi
  rm -f /tmp/smartx-workspace-xcodebuild.$$

  echo "WORKSPACE READY"
  echo "Workspace XML is valid, required FileRef targets exist, and xcodebuild can list the workspace."
  return 0
}

run_repair() {
  echo "Attempting non-destructive workspace repair..."
  (
    cd "$ROOT_DIR" || exit 1
    run_pod_install
  )
}

run_regeneration() {
  echo "Regenerating workspace and Pods because SMARTX_REGENERATE_WORKSPACE=1..."
  (
    cd "$ROOT_DIR" || exit 1
    rm -rf "$WORKSPACE_DIR" "$ROOT_DIR/Pods"
    if [ "$regenerate_lock" = "1" ]; then
      rm -f "$ROOT_DIR/Podfile.lock"
    fi
    run_pod_install
  )
}

cd "$ROOT_DIR" || exit 1

if [ "$regenerate_mode" = "1" ]; then
  if ! run_regeneration; then
    echo "Workspace regeneration failed."
    exit 2
  fi
  if validate_workspace; then
    exit 0
  fi
  echo "Workspace is still invalid after regeneration."
  exit 2
fi

if validate_workspace; then
  exit 0
fi

if [ "$repair_mode" = "1" ]; then
  if ! run_repair; then
    echo "Workspace repair failed."
    exit 2
  fi
  if validate_workspace; then
    exit 0
  fi
  echo "Workspace is still invalid after repair."
  echo "Destructive repair is available if you explicitly request it:"
  echo "  SMARTX_REGENERATE_WORKSPACE=1 bash scripts/ensure-xcworkspace.sh"
  exit 2
fi

exit 1
