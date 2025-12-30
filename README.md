# 📜 Changelog Generator

A lightweight, dependency-free CLI tool to generate beautiful changelogs
from your Git history based on
[Conventional Commits](https://www.conventionalcommits.org/).

Designed to be portable, fast, and easy to use in CI/CD pipelines
(GitHub Actions).

[🇷🇺 Читать на русском](docs/README.ru.md)

## ✨ Features

- **Zero Dependencies**: Written in pure Bash. Only requires `git`
    (and `curl`/`jq` for API features).
- **Automatic Range**: Automatically detects the latest tag and generates
    a changelog for unreleased changes.
- **Smart Grouping**: Groups commits by type (`feat`, `fix`, `perf`, etc.).
- **Squash Support**: Correctly handles "Squashed commits" from GitHub,
    grouping them visually under one parent hash.
- **Links Integration**: Can generate clickable links to commits and
    authors (GitHub API).
- **Portable**: Can be installed as a standalone CLI tool.

## 🚀 Installation

### CLI (Linux/macOS)

Install the latest version to `~/.local/bin` with a single command:

<!-- markdownlint-capture -->
<!-- markdownlint-disable MD013 -->
```bash
curl -fsSL https://raw.githubusercontent.com/alex2844/action-gh-changelog/main/install.sh | bash
```
<!-- markdownlint-restore -->

Or download the binary manually from [Releases][releases].

### GitHub Actions

You can use this tool directly in your workflows without manual installation.

```yaml
- name: Generate Changelog
  uses: alex2844/action-gh-changelog@v1
  with:
    output: 'RELEASE_NOTES.md'
    # lang: 'ru' # Optional: language for headers (en/ru)
```

#### Action Inputs

| Input | Description | Default |
| :--- | :--- | :--- |
| `output` | Output file path. If not set, prints to stdout. | - |
| `tag` | Generate changelog for a specific tag. | `latest` |
| `since` | Start date/ref to fetch commits from. | - |
| `until` | End date/ref to fetch commits to. | - |
| `links` | Add links to commit hashes and authors. | `true` |
| `raw` | Output as a raw list without grouping. | `false` |
| `lang` | Language for headers (`en`, `ru`). | `en` |

## 📋 CLI Usage

```bash
changelog [OPTIONS]
```

### Options

| Flag | Long Flag | Description |
| :--- | :--- | :--- |
| `-t` | `--tag` | Tag to generate the changelog for. |
| `-o` | `--output` | Output file path (default: stdout). |
| `-s` | `--since` | Start date (e.g. `'2025-01-01'`). |
| `-u` | `--until` | End date. |
| `-l` | `--links` | Add links to commit hashes and authors. |
| `-r` | `--raw` | Output raw list without grouping. |
| `-q` | `--quiet` | Quiet mode (errors only). |
| `-v` | `--version` | Show version. |
| `-h` | `--help` | Show help. |

### Examples

**1. Generate changelog for unreleased changes (printed to console):**

```bash
changelog
```

**2. Generate release notes for a specific tag and save to file:**

```bash
changelog -t v1.0.0 -l -o notes.md
```

**3. Get a raw list of commits for the last month:**

```bash
changelog --since "1 month ago" --raw
```

## 📝 Commit Convention

The script expects your commits to follow the
[Conventional Commits](https://www.conventionalcommits.org/) specification.
Here are the main types recognized by the script:

- **`feat`** (🚀 Features): A new feature.
- **`fix`** (🐛 Bug Fixes): A bug fix.
- **`refactor`** (✨ Improvements): A code change that neither fixes a bug
    nor adds a feature.
- **`perf`** (✨ Improvements): A code change that improves performance.
- **`revert`** (⏪ Reverted Changes): Reverts a previous commit.
- **`docs`** (📖 Documentation): Documentation only changes.
- **`ci`** (⚙️ Continuous Integration): Changes to CI configuration
    files and scripts.
- **`chore`** (🔧 Miscellaneous): Other changes that don't modify src
    or test files.

## 🤝 Contributing

We welcome contributions! If you find a bug or have an idea, please
open an [Issue][issues].\
If you want to help with code, we welcome your [Pull Requests][pulls].

[issues]: https://github.com/alex2844/action-gh-changelog/issues
[pulls]: https://github.com/alex2844/action-gh-changelog/pulls
[releases]: https://github.com/alex2844/action-gh-changelog/releases
