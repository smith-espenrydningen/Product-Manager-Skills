#!/usr/bin/env bash
#
# test-a-skill.sh - Validate skill quality and integrity
#
# Default checks:
#   1) Strict conformance via scripts/check-skill-metadata.py
#   2) Linked skill paths (skills/*/SKILL.md) resolve
#   3) Security: invisible Unicode characters (steganography)
#   4) Security: prompt injection patterns
#   5) Security: dangerous imports in embedded scripts
#
# Optional checks:
#   --smoke:
#     - Non-empty core sections
#     - Interactive skills include numbered options in Application
#
# Usage:
#   ./scripts/test-a-skill.sh
#   ./scripts/test-a-skill.sh --skill user-story
#   ./scripts/test-a-skill.sh --skill skills/user-story/SKILL.md --smoke
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$SCRIPT_DIR/check-skill-metadata.py"

RUN_SMOKE=false
SKILL_ARGS=()

TOTAL=0
PASS=0
FAIL=0
WARN=0

require_value() {
    local option="$1"
    local value="${2:-}"
    if [[ -z "$value" || "$value" == -* ]]; then
        echo "Error: Option '$option' requires a value." >&2
        exit 1
    fi
}

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Test skill conformance and integrity.

Options:
  --skill <name|path>  Test one skill (repeatable)
  --smoke              Run additional prompt/readiness smoke checks
  --help, -h           Show this help

Examples:
  $0
  $0 --skill user-story
  $0 --skill skills/user-story/SKILL.md --smoke
  $0 --skill feature-investment-advisor --skill finance-based-pricing-advisor
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skill)
                require_value "--skill" "${2:-}"
                SKILL_ARGS+=("$2")
                shift 2
                ;;
            --smoke)
                RUN_SMOKE=true
                shift
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            -*)
                echo "Error: Unknown option '$1'." >&2
                echo "Run '$0 --help' for usage."
                exit 1
                ;;
            *)
                SKILL_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

extract_frontmatter_field() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        BEGIN { in_frontmatter = 0 }
        NR == 1 && $0 == "---" { in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { exit }
        in_frontmatter {
            if ($0 ~ "^" field ":[[:space:]]*") {
                sub("^" field ":[[:space:]]*", "", $0)
                print $0
                exit
            }
        }
    ' "$file"
}

resolve_skill_path() {
    local input="$1"
    local path=""

    absolute_path() {
        local value="$1"
        if [[ -d "$value" ]]; then
            (cd "$value" && pwd)
        else
            (cd "$(dirname "$value")" && printf "%s/%s\n" "$(pwd)" "$(basename "$value")")
        fi
    }

    if [[ -f "$input" && "$(basename "$input")" == "SKILL.md" ]]; then
        absolute_path "$input"
        return 0
    fi

    if [[ -d "$input" && -f "$input/SKILL.md" ]]; then
        path="$input/SKILL.md"
        absolute_path "$path"
        return 0
    fi

    if [[ -f "$PROJECT_ROOT/skills/$input/SKILL.md" ]]; then
        path="$PROJECT_ROOT/skills/$input/SKILL.md"
        absolute_path "$path"
        return 0
    fi

    if [[ -f "$PROJECT_ROOT/$input" && "$(basename "$input")" == "SKILL.md" ]]; then
        path="$PROJECT_ROOT/$input"
        absolute_path "$path"
        return 0
    fi

    return 1
}

section_body() {
    local file="$1"
    local heading="$2"
    awk -v heading="## $heading" '
        $0 == heading { in_section = 1; next }
        in_section && /^## / { exit }
        in_section { print }
    ' "$file"
}

section_has_content() {
    local file="$1"
    local heading="$2"
    local content
    content="$(section_body "$file" "$heading" | sed '/^[[:space:]-]*$/d' || true)"
    [[ "$content" =~ [[:alnum:]] ]]
}

check_linked_skill_paths() {
    local file="$1"
    local missing=0

    while IFS= read -r ref; do
        [[ -n "$ref" ]] || continue
        if [[ ! -f "$PROJECT_ROOT/$ref" ]]; then
            echo "    FAIL link missing: $ref"
            missing=$((missing + 1))
        fi
    done < <(rg -o --no-line-number "skills/[a-z0-9-]+/SKILL\\.md" "$file" | sort -u)

    return "$missing"
}

run_smoke_checks() {
    local file="$1"
    local type="$2"
    local smoke_fail=0
    local smoke_warn=0

    for section in "Purpose" "Key Concepts" "Application" "Examples" "Common Pitfalls" "References"; do
        if ! section_has_content "$file" "$section"; then
            echo "    FAIL smoke: section '$section' is empty"
            smoke_fail=$((smoke_fail + 1))
        fi
    done

    if [[ "$type" == "interactive" ]]; then
        local option_count question_count
        option_count="$(section_body "$file" "Application" | rg -n "^[[:space:]]*[0-9]+\\." | wc -l | tr -d ' ')"
        question_count="$(section_body "$file" "Application" | rg -o "\\?" | wc -l | tr -d ' ')"

        if [[ "$option_count" -lt 3 ]]; then
            echo "    WARN smoke: interactive skill should include >=3 numbered options in Application (found $option_count)"
            smoke_warn=$((smoke_warn + 1))
        fi

        if [[ "$question_count" -lt 1 ]]; then
            echo "    WARN smoke: no question marks detected in Application for interactive flow"
            smoke_warn=$((smoke_warn + 1))
        fi
    fi

    WARN=$((WARN + smoke_warn))
    return "$smoke_fail"
}

# Security: detect invisible Unicode characters (steganography risk)
check_invisible_unicode() {
    local file="$1"
    local hits
    hits=$(python3 -c "
import re, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    content = f.read()
invisible = re.compile(r'[\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF\u00AD\u034F\u180E]')
matches = invisible.findall(content)
if matches:
    chars = sorted(set(f'U+{ord(c):04X}' for c in matches))
    print(f'{len(matches)} invisible char(s): {\" \".join(chars)}')
" "$file" 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
        echo "    FAIL security: invisible Unicode detected — $hits"
        return 1
    fi
    return 0
}

# Security: detect prompt injection patterns in skill content
check_prompt_injection() {
    local file="$1"
    local injection_fail=0

    # Patterns that should never appear in legitimate skill content
    local -a patterns=(
        'ignore (previous|prior|above|all) instructions'
        'you are now [a-zA-Z]'
        'from now on,? (you|always|never)'
        'disregard (your|all|any|previous)'
        'new (system|base) prompt'
        'pretend you are'
        'act as if your (instructions|rules|guidelines)'
        'override (your|all|the|any) (instructions|rules|guidelines|safety)'
        'do not (reveal|disclose|mention|tell).*(system|prompt|instructions)'
        'send (data|info|content|context|conversation) to'
        'fetch (from|url|http)'
        'execute (this|the following) (code|command|script)'
    )

    for pattern in "${patterns[@]}"; do
        local match
        match=$(grep -Pic "$pattern" "$file" 2>/dev/null || true)
        if [[ "$match" -gt 0 ]]; then
            echo "    FAIL security: prompt injection pattern detected — '$pattern' ($match match(es))"
            injection_fail=$((injection_fail + 1))
        fi
    done

    return "$injection_fail"
}

# Security: detect dangerous imports in embedded Python scripts
check_script_imports() {
    local skill_dir="$1"
    local scripts_dir="$skill_dir/scripts"
    local import_fail=0

    [[ -d "$scripts_dir" ]] || return 0

    local script
    for script in "$scripts_dir"/*.py; do
        [[ -f "$script" ]] || continue
        local script_name
        script_name="$(basename "$script")"

        # Dangerous modules: network I/O, shell execution, code generation
        local -a forbidden=(
            'import requests'
            'from requests '
            'import urllib'
            'from urllib '
            'import socket'
            'from socket '
            'import subprocess'
            'from subprocess '
            'import shutil'
            'from shutil '
            'os\.system\s*\('
            'os\.popen\s*\('
            'os\.exec'
            'eval\s*\('
            'exec\s*\('
            'compile\s*\('
            '__import__\s*\('
        )

        for pattern in "${forbidden[@]}"; do
            local match
            match=$(grep -Pc "$pattern" "$script" 2>/dev/null || true)
            if [[ "$match" -gt 0 ]]; then
                echo "    FAIL security: dangerous pattern '$pattern' in scripts/$script_name"
                import_fail=$((import_fail + 1))
            fi
        done
    done

    return "$import_fail"
}

test_one_skill() {
    local file="$1"
    local skill_name skill_type
    local failed=0

    TOTAL=$((TOTAL + 1))
    skill_name="$(extract_frontmatter_field "$file" "name")"
    skill_type="$(extract_frontmatter_field "$file" "type")"

    echo ""
    echo "Testing: $skill_name ($skill_type)"
    echo "  file: ${file#"$PROJECT_ROOT"/}"

    if python3 "$VALIDATOR" "$file" >/dev/null 2>&1; then
        echo "    PASS conformance"
    else
        echo "    FAIL conformance"
        failed=$((failed + 1))
    fi

    if check_linked_skill_paths "$file"; then
        echo "    PASS linked skill paths"
    else
        echo "    FAIL linked skill paths"
        failed=$((failed + 1))
    fi

    if check_invisible_unicode "$file"; then
        echo "    PASS security: no invisible Unicode"
    else
        failed=$((failed + 1))
    fi

    if check_prompt_injection "$file"; then
        echo "    PASS security: no prompt injection patterns"
    else
        failed=$((failed + 1))
    fi

    local skill_dir
    skill_dir="$(dirname "$file")"
    if check_script_imports "$skill_dir"; then
        if [[ -d "$skill_dir/scripts" ]]; then
            echo "    PASS security: embedded scripts clean"
        fi
    else
        failed=$((failed + 1))
    fi

    if $RUN_SMOKE; then
        if run_smoke_checks "$file" "$skill_type"; then
            echo "    PASS smoke checks"
        else
            echo "    FAIL smoke checks"
            failed=$((failed + 1))
        fi
    fi

    if [[ "$failed" -eq 0 ]]; then
        PASS=$((PASS + 1))
        echo "  RESULT: PASS"
    else
        FAIL=$((FAIL + 1))
        echo "  RESULT: FAIL"
    fi
}

main() {
    parse_args "$@"

    if [[ ! -f "$VALIDATOR" ]]; then
        echo "Error: Missing validator: $VALIDATOR" >&2
        exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required for validation." >&2
        exit 1
    fi

    local targets=()

    if [[ ${#SKILL_ARGS[@]} -eq 0 ]]; then
        while IFS= read -r file; do
            targets+=("$file")
        done < <(find "$PROJECT_ROOT/skills" -mindepth 2 -maxdepth 2 -name "SKILL.md" | sort)
    else
        local arg resolved
        for arg in "${SKILL_ARGS[@]}"; do
            if resolved="$(resolve_skill_path "$arg")"; then
                targets+=("$resolved")
            else
                echo "Error: Could not resolve skill: $arg" >&2
                exit 1
            fi
        done
    fi

    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "No skills found to test."
        exit 1
    fi

    local file
    for file in "${targets[@]}"; do
        test_one_skill "$file"
    done

    echo ""
    echo "Summary:"
    echo "  total: $TOTAL"
    echo "  pass:  $PASS"
    echo "  fail:  $FAIL"
    echo "  warn:  $WARN"

    if [[ "$FAIL" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
