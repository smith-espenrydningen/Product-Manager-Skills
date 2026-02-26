# Security Policy

## Scope

This repository is a **content and documentation project** containing Product Manager skill definitions (Markdown files), helper shell scripts, and a Python validation script. It does not include application code, web servers, APIs, or databases.

The primary security surface is:
1. **Skill files** (`skills/*/SKILL.md`) that get loaded as system-level instructions into AI agents
2. **Automation scripts** (`scripts/`) that parse AI-generated output and manipulate files on disk

## Supported Versions

Only the latest release on the `main` branch is supported with security fixes.

## Reporting a Vulnerability

If you discover a security issue, please report it by opening an issue on this repository or emailing the repository maintainers directly.

Please include:
- Description of the vulnerability
- Steps to reproduce
- Affected file(s) and line number(s)
- Suggested fix (if any)

We aim to acknowledge reports within 48 hours and resolve confirmed issues within 7 days.

## Security Measures

### Shell Scripts (`scripts/`)

- All scripts use `set -euo pipefail` for strict error handling
- All scripts pass [ShellCheck](https://www.shellcheck.net/) with zero warnings
- **Filename sanitization** strips unsafe characters from AI-generated filenames before writing to disk (adapters only allow `[a-zA-Z0-9._/-]`)
- **Path traversal protection** rejects absolute paths, `..` sequences, and tilde expansion
- **Safe `rm -rf`** operations validate that target paths are non-empty, non-root, and under an expected prefix before deletion
- **Temporary directories** use `mktemp -d` with cleanup traps that validate the `/tmp` prefix
- **Content validation gate** in adapter scripts scans every AI-generated file for prompt injection patterns before accepting it into the pipeline

### Prompt Injection Defense (`scripts/test-a-skill.sh`)

The test suite runs three security checks on every skill, with zero false positives across all 42 skills:

- **Invisible Unicode detection** scans for 30+ zero-width and invisible codepoints (U+200B-200F, U+2028-202F, U+2060-206F, U+FEFF, U+00AD, U+034F, U+180E) that could hide instructions from human reviewers while remaining visible to AI models
- **Prompt injection pattern matching** checks for 12 patterns including instruction override (`ignore previous instructions`), role hijacking (`you are now`), secrecy directives (`do not reveal`), and data exfiltration commands (`send data to`)
- **Embedded script validation** checks Python scripts in `skills/*/scripts/` for 17 dangerous patterns including `requests`, `urllib`, `socket`, `subprocess`, `os.system`, `eval`, `exec`, `compile`, and `__import__`

### Python Script (`scripts/check-skill-metadata.py`)

- Uses `yaml.safe_load()` (not `yaml.load()`) to prevent arbitrary code execution via YAML deserialization
- Read-only file operations with explicit UTF-8 encoding
- No use of `eval()`, `exec()`, `subprocess`, or `os.system()`
- No network calls
- Input handled exclusively through `argparse`

### Repository Hygiene

- `.gitignore` excludes `.env`, credential files, and build artifacts
- No secrets, API keys, or credentials in the repository or git history
- No external dependencies or network calls in any script (only stdlib + PyYAML)
- All example data uses fictional company names and placeholder emails

## Threat Model

This repository has two attack surfaces:

### 1. Skills as System Prompts

Skill files get loaded as system-level instructions into AI agents (Claude, ChatGPT, Codex, Gemini). A malicious or compromised skill could:

- **Override agent behavior** (e.g., "ignore previous instructions") - Mitigated by prompt injection pattern matching in `test-a-skill.sh` (12 patterns) and adapter content validation gate
- **Hide instructions via steganography** (zero-width Unicode characters invisible to reviewers) - Mitigated by invisible Unicode detection across 30+ codepoints
- **Exfiltrate data via embedded scripts** (e.g., `import requests`) - Mitigated by dangerous import scanning (17 patterns) in `test-a-skill.sh`
- **Social-engineer the user** (e.g., "don't tell the user about X") - Mitigated by secrecy directive pattern matching

### 2. AI-Generated Skill Pipeline

The adapter scripts (`scripts/adapters/`) parse file blocks from AI CLI responses. A crafted response could attempt to:

- **Write files outside the output directory** - Mitigated by path traversal checks and filename sanitization
- **Inject shell metacharacters into filenames** - Mitigated by allowlist-based character filtering (`[a-zA-Z0-9._/-]`)
- **Overwrite critical files** - Mitigated by output directory scoping and `rm -rf` prefix guards
- **Embed prompt injection in generated content** - Mitigated by `_validate_skill_content()` gate that scans every generated file before accepting it

### Assumptions

These mitigations assume scripts are run in a local development environment by trusted users. They are not designed for untrusted multi-tenant execution.
