#!/usr/bin/env bash
# script.sh - CLI entry point for agent-todo skill
#
# Usage:
#   ./script.sh add "title" --deadline "..." --owner "..." --source "..."
#   ./script.sh list [--owner X] [--status pending] [--upcoming 24]
#   ./script.sh done <id> --note "..."
#   ./script.sh cancel <id> --reason "..."
#   ./script.sh check-overdue
#   ./script.sh show <id>
#   ./script.sh init

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$SCRIPT_DIR"

# Load library
# shellcheck source=todo_lib.sh
source "${SKILL_DIR}/todo_lib.sh"

# Entry point delegates to todo.sh
exec "${SKILL_DIR}/todo.sh" "$@"
