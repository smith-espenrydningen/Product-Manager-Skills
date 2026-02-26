# Security Policy

## Scope

This repository is a **content and documentation project** containing Product Manager skill definitions (Markdown files), helper shell scripts, and a Python validation script. It does not include application code, web servers, APIs, or databases.

The primary security surface is the **automation scripts** in `scripts/` that parse AI-generated output and manipulate files on disk.

## Supported Versions

Only the latest release on the `main` branch is supported with security fixes.

## Reporting a Vulnerability

If you discover a security issue, please report it by [opening a private issue](https://github.com/smith-espenrydningen/Product-Manager-Skills/issues/new) or emailing the repository maintainers directly.

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

The main risk vector for this repository is **prompt injection via AI-generated output**. The adapter scripts (`scripts/adapters/`) parse file blocks from AI CLI responses. A crafted response could attempt to:

1. **Write files outside the output directory** - Mitigated by path traversal checks and filename sanitization
2. **Inject shell metacharacters into filenames** - Mitigated by allowlist-based character filtering
3. **Overwrite critical files** - Mitigated by output directory scoping and `rm -rf` prefix guards

These mitigations assume scripts are run in a local development environment by trusted users. They are not designed for untrusted multi-tenant execution.
