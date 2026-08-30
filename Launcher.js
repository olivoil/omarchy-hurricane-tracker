function trimTrailingSlashes(value) {
  var path = String(value || "")
  while (path.length > 1 && path.charAt(path.length - 1) === "/")
    path = path.slice(0, -1)
  return path
}

function absolutePathOr(value, fallback) {
  var path = trimTrailingSlashes(value)
  return path.charAt(0) === "/" ? path : fallback
}

function dataHome(xdgDataHome, home) {
  var fallback = trimTrailingSlashes(home) + "/.local/share"
  return absolutePathOr(xdgDataHome, fallback)
}

function runtimeHome(xdgRuntimeDir, xdgCacheHome, home) {
  var fallback = trimTrailingSlashes(home) + "/.cache"
  return absolutePathOr(xdgRuntimeDir, absolutePathOr(xdgCacheHome, fallback))
}

// Every launcher state change is written synchronously before this detached
// reconciler starts. The shared lock makes concurrent workers read and apply
// the latest intent in one critical section, regardless of their start order.
var launcherEntryScript =
  'state=$1\n'
  + 'template=$2\n'
  + 'destination=$3\n'
  + 'marker=$4\n'
  + 'icon=$5\n'
  + '(\n'
  + '  flock 9 || exit 0\n'
  + '  IFS= read -r desired < "$state" || exit 0\n'
  + '  case "$desired" in\n'
  + '    install)\n'
  + '      [ -f "$template" ] || exit 0\n'
  + '      if [ -e "$destination" ] && ! grep -Fqx -- "$marker" "$destination"; then exit 0; fi\n'
  + '      mkdir -p -- "${destination%/*}" || exit 0\n'
  + '      tmp="${destination}.hurricane-tracker.new.$$"\n'
  + '      trap \'rm -f -- "$tmp"\' EXIT\n'
  + '      while IFS= read -r line || [ -n "$line" ]; do\n'
  + '        if [ "$line" = "Icon=@ICON@" ]; then printf "Icon=%s\\n" "$icon";\n'
  + '        else printf "%s\\n" "$line"; fi\n'
  + '      done < "$template" > "$tmp" || exit 0\n'
  + '      if ! cmp -s -- "$tmp" "$destination"; then mv -f -- "$tmp" "$destination" || exit 0; fi\n'
  + '      ;;\n'
  + '    remove)\n'
  + '      if grep -Fqx -- "$marker" "$destination" 2>/dev/null; then rm -f -- "$destination"; fi\n'
  + '      ;;\n'
  + '  esac\n'
  + ') 9>"${state}.lock"\n'
