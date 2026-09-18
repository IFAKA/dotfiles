#!/usr/bin/env bash
set -u

script_dir=$(cd -P "$(dirname "$0")" && pwd)
source "$script_dir/vercel-deploy-common.sh"
directory=${1:-}
[[ -n "$directory" && -d "$directory" ]] || exit 0
root=$(vercel_find_root "$directory") || exit 0
project_file="$root/.vercel/project.json"
project_id=$(vercel_json_value projectId "$project_file")
[[ -n "$project_id" ]] || exit 0
cache_file=$(vercel_cache_file "$root" "$project_id")

case "$(cat "$cache_file" 2>/dev/null)" in
  ready) printf '#[fg=colour255,bg=#166534,bold] ▲ #[default]\n' ;;
  deploying)
    frames=(▲ ▶ ▼ ◀)
    printf '#[fg=colour232,bg=#a16207,bold] %s #[default]\n' "${frames[$(( $(date +%s) % 4 ))]}"
    ;;
  failed) printf '#[fg=colour255,bg=#991b1b,bold] ▲ #[default]\n' ;;
  unavailable) printf '#[fg=colour255,bg=colour238,bold] ▲ #[default]\n' ;;
esac
