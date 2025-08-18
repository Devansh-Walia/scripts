#!/usr/bin/env bash
set -euo pipefail

# run-all-repos.sh
# - Finds repos with pnpm-lock.yaml or yarn.lock
# - Installs dependencies with the matching package manager
# - Runs the app using "dev" or "start" if present
#
# Usage:
#   scripts/run-all-repos.sh [--no-run] [--dry-run] [--max-depth N] [--concurrency N]
# Options:
#   --no-run        Only install deps; do not run scripts
#   --dry-run       Print what would be done without executing commands
#   --max-depth N   How deep to search for repos (default: 3)
#   --concurrency N How many installs/runs to do in parallel (default: 1)
#
# Notes:
# - Prefers pnpm when pnpm-lock.yaml is present; otherwise yarn when yarn.lock is present
# - For run step, prefers `dev`, then `start`
# - Each repo logs to logs/<repo-name>.log when running

NO_RUN=0
DRY_RUN=0
MAX_DEPTH=3
CONCURRENCY=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-run)
      NO_RUN=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --max-depth)
      MAX_DEPTH=${2:-3}
      shift 2
      ;;
    --concurrency)
      CONCURRENCY=${2:-1}
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Colors
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; RED="$(tput setaf 1)"; RESET="$(tput sgr0)"
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

log_info() { echo "${BOLD}${GREEN}[INFO]${RESET} $*"; }
log_warn() { echo "${BOLD}${YELLOW}[WARN]${RESET} $*"; }
log_err()  { echo "${BOLD}${RED}[ERR ]${RESET} $*"; }

# Verify tools
need_tool() {
  local t="$1"; local hint="$2"
  if ! command -v "$t" >/dev/null 2>&1; then
    log_warn "Missing '$t'. ${hint}"
    return 1
  fi
  return 0
}

# Check optional managers; we warn later if a repo needs one that is missing
need_tool node "Install Node.js to inspect package.json scripts (e.g., via nvm)." || true
need_tool pnpm "Install pnpm: corepack enable && corepack prepare pnpm@latest --activate" || true
need_tool yarn "Install yarn: corepack enable && corepack prepare yarn@stable --activate" || true

# Helper: check if a package.json has a given script
has_script() {
  local dir="$1"; local script="$2"
  if [[ ! -f "$dir/package.json" ]]; then
    return 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    # If node missing, we can't inspect; assume not present
    return 1
  fi
  node -e "try{const p=require(process.argv[1]);process.exit(p.scripts&&p.scripts[process.argv[2]]?0:1)}catch(e){process.exit(1)}" "$dir/package.json" "$script"
}

repo_runner() {
  local dir="$1"
  local manager=""
  local lock=""

  if [[ -f "$dir/pnpm-lock.yaml" ]]; then
    manager="pnpm"; lock="pnpm-lock.yaml"
  elif [[ -f "$dir/yarn.lock" ]]; then
    manager="yarn"; lock="yarn.lock"
  else
    log_warn "Skipping $dir (no pnpm-lock.yaml or yarn.lock)"
    return 0
  fi

  log_info "Processing $dir using $manager (lock: $lock)"

  # Install
  if (( DRY_RUN )); then
    echo "DRY_RUN: (cd '$dir' && $manager install --frozen-lockfile)"
  else
    if [[ "$manager" == "pnpm" ]]; then
      if ! command -v pnpm >/dev/null 2>&1; then
        log_err "pnpm not installed; cannot process $dir"
        return 1
      fi
      (cd "$dir" && pnpm install --frozen-lockfile)
    else
      if ! command -v yarn >/dev/null 2>&1; then
        log_err "yarn not installed; cannot process $dir"
        return 1
      fi
      (cd "$dir" && yarn install --frozen-lockfile)
    fi
  fi

  # Run
  if (( NO_RUN )); then
    log_info "--no-run: Skipping run step for $dir"
    return 0
  fi

  local script=""
  if has_script "$dir" dev; then script="dev"; elif has_script "$dir" start; then script="start"; fi

  if [[ -z "$script" ]]; then
    log_warn "No 'dev' or 'start' script found in $dir/package.json; skipping run"
    return 0
  fi

  mkdir -p logs
  local name
  name="$(basename "$dir")"
  local log_file="logs/${name}.log"

  if (( DRY_RUN )); then
    echo "DRY_RUN: (cd '$dir' && $manager $script) > '$log_file' 2>&1 &"
  else
    log_info "Starting $name: $manager $script (logging to $log_file)"
    if [[ "$manager" == "pnpm" ]]; then
      (cd "$dir" && pnpm "$script") >"$log_file" 2>&1 &
    else
      (cd "$dir" && yarn "$script") >"$log_file" 2>&1 &
    fi
  fi
}

export -f repo_runner
export -f log_info
export -f log_warn
export -f log_err
export -f has_script

# Discover candidate directories (portable across older macOS bash)
REPOS=()
# Collect lockfile directories, unique
while IFS= read -r -d '' file; do
  dir=$(dirname "$file")
  REPOS+=("$dir")
done < <(find . -maxdepth "$MAX_DEPTH" -type f \( -name 'pnpm-lock.yaml' -o -name 'yarn.lock' \) -print0)
# Deduplicate
if [[ ${#REPOS[@]} -gt 0 ]]; then
  # Print, sort -u, and read back
  UNIQUE_REPOS=()
  while IFS= read -r line; do UNIQUE_REPOS+=("$line"); done < <(printf '%s\n' "${REPOS[@]}" | sort -u)
  REPOS=("${UNIQUE_REPOS[@]}")
fi

if [[ ${#REPOS[@]} -eq 0 ]]; then
  log_warn "No repositories with pnpm-lock.yaml or yarn.lock found within max depth $MAX_DEPTH"
  exit 0
fi

log_info "Found ${#REPOS[@]} repositories"

# Run sequentially or with limited concurrency
if (( CONCURRENCY <= 1 )); then
  for dir in "${REPOS[@]}"; do
    repo_runner "$dir" || true
  done
else
  if command -v xargs >/dev/null 2>&1; then
    printf '%s\n' "${REPOS[@]}" | xargs -I{} -P "$CONCURRENCY" bash -c 'repo_runner "$@"' _ {}
  else
    log_warn "xargs not available; falling back to sequential execution"
    for dir in "${REPOS[@]}"; do
      repo_runner "$dir" || true
    done
  fi
fi

log_info "Done. If any apps were started, check the logs/ directory for output."

