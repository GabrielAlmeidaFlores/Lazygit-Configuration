# LazyGit Enhanced Configuration

A powerful LazyGit configuration with automated workflows, AI-powered code review, and beautiful theme integration.

## Features

### Automation & Intelligence

- **AI PR Review** - Analyze open PRs for architecture, security, code quality, test coverage and performance issues, then post natural comments directly on GitHub
- **AI-Powered Commit Messages** - Generate professional, conventional commit messages with gitmoji
- **AI-Powered Branch Names** - Generate descriptive branch names with automatic emoji prefixes
- **AI Thinking Output** - See the AI reasoning process in real-time as it generates results
- **Multi-Provider AI** - Switch between Cursor Agent and GitHub Copilot via `config.env`
- **Configurable AI Model** - Select the model interactively at runtime or set a default in `config.env`

### User Experience

- **Human-in-the-Loop** - Review and edit all suggestions before applying
- **Interactive Editing** - Integrated editor support (nano, vim, etc.)
- **Optional Context Input** - Provide additional context to the AI for better results
- **English Standardization** - Consistent English-only output for international teams

### Customization

- **Dracula Theme** - Complete color scheme integration
- **Modular Architecture** - Easy to extend and customize
- **Gateway Pattern** - Swap AI providers or add new integrations effortlessly
- **Config-driven Prompts** - All AI prompts live in `config.env`, no script editing needed

## Prerequisites

### Required

| Dependency | Purpose | Install |
|---|---|---|
| [LazyGit](https://github.com/jesseduffield/lazygit) | Terminal UI for git | `brew install lazygit` |
| [git-delta](https://github.com/dandavison/delta) | Syntax-highlighted diffs | `brew install git-delta` |
| [fzf](https://github.com/junegunn/fzf) | Interactive fuzzy selection menus | `brew install fzf` |
| [gh](https://cli.github.com/) | GitHub CLI (PR list, diff, comments) | `brew install gh` |
| [jq](https://jqlang.github.io/jq/) | JSON parsing for PR data | `brew install jq` |
| Git | Version control | pre-installed on macOS |
| Bash | Shell scripting | pre-installed on macOS |

### Install all at once (macOS)

```bash
brew install lazygit git-delta fzf gh jq
```

### git-delta (other platforms)

| Platform | Command |
|---|---|
| macOS | `brew install git-delta` |
| Fedora | `sudo dnf install git-delta` |
| Debian / Ubuntu | `sudo apt install git-delta` |
| Windows (Winget) | `winget install dandavison.delta` |
| Windows (Scoop) | `scoop install delta` |

> On older Debian/Ubuntu where `git-delta` is unavailable in apt, download a `.deb` from the [delta releases page](https://github.com/dandavison/delta/releases).

### fzf (other platforms)

| Platform | Command |
|---|---|
| macOS | `brew install fzf` |
| Fedora | `sudo dnf install fzf` |
| Debian / Ubuntu | `sudo apt install fzf` |
| Windows (Scoop) | `scoop install fzf` |

### gh — GitHub CLI (other platforms)

| Platform | Command |
|---|---|
| macOS | `brew install gh` |
| Fedora | `sudo dnf install gh` |
| Debian / Ubuntu | `sudo apt install gh` |
| Windows (Winget) | `winget install GitHub.cli` |

After installing, authenticate:

```bash
gh auth login
```

### jq (other platforms)

| Platform | Command |
|---|---|
| macOS | `brew install jq` |
| Fedora | `sudo dnf install jq` |
| Debian / Ubuntu | `sudo apt install jq` |
| Windows (Chocolatey) | `choco install jq` |

### Optional (for AI features)

- [Cursor Agent CLI](https://cursor.com/docs/cli) - Default AI provider (`agent` command)
- [GitHub Copilot CLI](https://www.npmjs.com/package/@github/copilot) - Alternative AI provider

## Installation

### 1. Clone the repository

```bash
git clone <this-repo> ~/Documents/Lazygit-Configuration
```

### 2. Create symbolic links

Link this repository to LazyGit's config directory so changes sync automatically:

```bash
# config file
ln -sf ~/Documents/Lazygit-Configuration/config.yml ~/.config/lazygit/config.yml

# scripts directory
ln -sf ~/Documents/Lazygit-Configuration/commands ~/.config/lazygit/commands

# environment config (scripts resolve this path at runtime)
ln -sf ~/Documents/Lazygit-Configuration/config.env ~/.config/lazygit/config.env
```

### 3. Make scripts executable

```bash
chmod +x ~/.config/lazygit/commands/*.sh
chmod +x ~/.config/lazygit/commands/gateways/*.sh
chmod +x ~/.config/lazygit/commands/gateways/adapters/*.sh
```

### 4. Add the `pr-review` terminal command

Add this alias to your `~/.zshrc` (or `~/.bashrc`):

```bash
echo 'alias pr-review="bash ~/.config/lazygit/commands/review_pr.sh"' >> ~/.zshrc
source ~/.zshrc
```

You can now run `pr-review` from any terminal in a git repository.

### 5. Install and authenticate your AI provider

**Cursor Agent (default):**

```bash
# Install via Cursor IDE settings or CLI docs
agent login
```

**GitHub Copilot:**

```bash
npm install -g @github/copilot
copilot auth
```

Set `AI_PROVIDER` in `config.env` to switch between providers.

## Quick Start

### Using Custom Commands inside LazyGit

| Key | Context | Action |
|---|---|---|
| `Ctrl+A` | Global | AI PR Review |
| `C` | Files | Generate AI commit message |
| `B` | Files | Generate AI branch name |

### Using `pr-review` from the terminal

```bash
cd your-repo
pr-review
```

## Available Commands

### AI PR Review (`Ctrl+A` or `pr-review`)

An interactive multi-step workflow to analyze open PRs and post comments on GitHub.

**Flow:**

1. **Select PR** — lists all open PRs via `fzf`
2. **Select AI model** — choose from provider-specific models (or use the default from `config.env`)
3. **Select analyses** — pick one or more (Tab to multi-select):
   - `Architecture` — separation of concerns, coupling, SOLID violations
   - `Security` — exposed secrets, injection risks, unsanitized inputs
   - `Code Quality` — duplication, complexity, poor naming, missing error handling
   - `Test Coverage` — missing tests, edge cases, untested critical logic
   - `Performance` — N+1 queries, inefficient loops, blocking operations
   - `All` — runs all five sequentially
4. **Fetch PR data** — pulls title, description, author and diff via `gh`
5. **AI analysis** — runs each selected analysis with a focused prompt
6. **Summary** — shows a `✅ / ⚠️` status per analysis and a full issues checklist
7. **Post comments** — optionally post one natural comment per issue on GitHub
   - Select language: PT, EN or ES
   - Review each generated comment before posting
   - Option to edit before posting

### Generate Commit Message (`C`)

1. Stage your changes in LazyGit
2. Press `C` in the files view
3. **(Optional)** Provide additional context
4. Review the generated message
5. Press `[Enter]` to commit or `[e]` to edit

### Generate Branch Name (`B`)

1. Stage your changes in LazyGit
2. Press `B` in the files view
3. **(Optional)** Provide additional context
4. Review the generated name with emoji
5. Press `[Enter]` to create the branch or `[e]` to edit

## Configuration

### AI Provider & Model

All AI settings live in `config.env`:

```bash
AI_PROVIDER="cursor"   # cursor | copilot
MODEL=""               # Leave empty for provider default
FALLBACK_MODEL=""      # Fallback model if primary fails
MAX_RETRIES=2
TIMEOUT=60
```

| Variable | Applies to | Description |
|---|---|---|
| `AI_PROVIDER` | All | Active provider: `cursor` or `copilot` |
| `MODEL` | All | Primary model (empty = provider default) |
| `FALLBACK_MODEL` | All | Fallback model if primary fails |
| `MAX_RETRIES` | All | Retry attempts per model |
| `TIMEOUT` | All | Request timeout in seconds |
| `CURSOR_BIN` | Cursor | Path to `agent` binary (empty = auto-detect) |
| `CURSOR_MODE` | Cursor | Agent mode: `ask` (default) or `plan` |
| `COPILOT_BIN` | Copilot | Path to `copilot` binary (empty = auto-detect) |

### PR Review — Model Selection

Customize which models appear in the interactive selector:

```bash
# Comma-separated. Leave empty to use built-in defaults.
CURSOR_MODELS="claude-4-5-sonnet,claude-4-5,gpt-4o,o3"
COPILOT_MODELS="claude-3.7-sonnet,gpt-4o,o3"
```

**Cursor defaults:** `claude-4-5-sonnet, claude-4-5, claude-4-opus, gpt-4o, gpt-4.1, o3, gemini-2.5-pro`

**Copilot defaults:** `claude-3.5-sonnet, claude-3.7-sonnet, gpt-4o, gpt-4.1, o3`

### PR Review — Customizing Prompts

All prompts used by `pr-review` are defined in `config.env`. Edit them directly — no script changes needed.

**Per-analysis instructions:**

```bash
PROMPT_INSTRUCTIONS_ARQUITETURA="Check for: ..."
PROMPT_INSTRUCTIONS_SEGURANCA="Check for: ..."
PROMPT_INSTRUCTIONS_QUALIDADE="Check for: ..."
PROMPT_INSTRUCTIONS_TESTES="Check for: ..."
PROMPT_INSTRUCTIONS_PERFORMANCE="Check for: ..."
```

**Analysis prompt template** (sent to AI for each analysis):

```bash
PROMPT_ANALYSIS_TEMPLATE="You are a senior software engineer...
Analyze ONLY for: __ANALYSIS_NAME__
PR TITLE: __PR_TITLE__
..."
```

**Comment generation template** (generates the PR comment per issue):

```bash
PROMPT_COMMENT_TEMPLATE="You are a developer writing a code review comment...
Write a comment in __COMMENT_LANG__ about: __ISSUE__
..."
```

**Available placeholders:**

| Placeholder | Value |
|---|---|
| `__ANALYSIS_NAME__` | Current analysis type (e.g. `Security`) |
| `__PR_TITLE__` | PR title |
| `__PR_AUTHOR__` | PR author login |
| `__PR_BODY__` | PR description |
| `__PR_DIFF__` | First 400 lines of the PR diff |
| `__INSTRUCTIONS__` | Per-analysis instruction text |
| `__ISSUE__` | A single issue found during analysis |
| `__COMMENT_LANG__` | Comment language (e.g. `Brazilian Portuguese`) |

### Theme Customization

The configuration includes a complete Dracula theme. Modify colors in `config.yml`:

```yaml
gui:
  theme:
    activeBorderColor: ["#bd93f9", "bold"]
    stagedChangesColor: ["#50fa7b"]
    unstagedChangesColor: ["#ff5555"]
```

## File Structure

```
~/.config/lazygit/
├── commands/
│   ├── gateways/
│   │   ├── generative-ia.sh          # AI gateway — routes to active provider
│   │   └── adapters/
│   │       ├── _helpers.sh           # Shared timeout utilities
│   │       ├── cursor.sh             # Cursor Agent adapter
│   │       └── copilot.sh            # GitHub Copilot adapter
│   ├── review_pr.sh                  # AI PR Review (pr-review command)
│   ├── gen_commit_with_ia.sh         # Commit message generator
│   └── gen_branch_with_ia.sh        # Branch name generator
├── config.env                        # AI config: provider, model, prompts
├── config.yml                        # LazyGit config, theme & keybindings
└── README.md
```

## Standards & Conventions

### Commit Message Format

```
<gitmoji> <type>(<scope>): <summary>

- <Detailed Bullet Points>
```

### Type Mapping

| Type | Emoji | Description |
|---|---|---|
| feat | ✨ | New logic/functionality |
| fix | 🐛 | Bug fixes |
| refactor | ♻️ | Code refactoring/cleaning |
| chore | 🔧 | Build/Config/CI/Docker |
| docs | 📝 | Documentation/Comments |
| style | 💄 | CSS/Styling/UI |

### Branch Name Format

```
<emoji><type>/<descriptive-name>
```

Example: `🐛fix/auth-token-validation`

| Prefix | Emoji | Description |
|---|---|---|
| fix/ | 🐛 | Bug fixes and corrections |
| feat/ | ✨ | New features and modules |
| chore/ | 🔨 | Config, deps, docker, CI, build |
| refactor/ | ♻️ | Code structure changes |
| docs/ | 📝 | Documentation and markdown |
| style/ | 💄 | CSS/Styling/UI changes |
| test/ | ✅ | Test additions/modifications |
| perf/ | ⚡ | Performance improvements |

## Troubleshooting

### `fzf` not found

```bash
brew install fzf        # macOS
sudo apt install fzf    # Debian/Ubuntu
sudo dnf install fzf    # Fedora
```

### `gh` not found or not authenticated

```bash
brew install gh
gh auth login
```

### `jq` not found

```bash
brew install jq         # macOS
sudo apt install jq     # Debian/Ubuntu
```

### AI features not working

- Verify your provider is installed and authenticated (`agent login` or `copilot auth`)
- Check `AI_PROVIDER` in `config.env` matches your installed provider
- Test the gateway directly: `./commands/gateways/generative-ia.sh "hello"`

### No open PRs found

- Make sure you are inside a git repository with a GitHub remote
- Make sure `gh` is authenticated: `gh auth status`
- Check you have open PRs: `gh pr list`

### No staged changes (commit/branch commands)

- Stage files in LazyGit with `[Space]` before pressing `C` or `B`

### Permission denied

```bash
chmod +x ~/.config/lazygit/commands/**/*.sh
```

### Editor not opening

```bash
export EDITOR=nano   # or vim, code, etc.
# Add to ~/.zshrc to make permanent
```

## Extending & Customizing

### Adding a new command

1. Create a script in `commands/` (e.g. `commands/gen_something.sh`)
2. Source the gateway: `source "$SCRIPT_DIR/gateways/generative-ia.sh"`
3. Call `generative_ia "$PROMPT"` with your prompt
4. Add a keybinding in `config.yml`

### Adding a new AI provider

1. Create `commands/gateways/adapters/<provider>.sh` with a `_generative_ia_<provider>()` function
2. Register it in `generative-ia.sh` under the `case "$PROVIDER"` block
3. Set `AI_PROVIDER="<provider>"` in `config.env`

## Credits

- [LazyGit](https://github.com/jesseduffield/lazygit) — Amazing terminal UI for git
- [Dracula Theme](https://draculatheme.com/) — Beautiful color scheme
- [Conventional Commits](https://www.conventionalcommits.org/) — Commit message standard
- [Gitmoji](https://gitmoji.dev/) — Emoji guide for commit messages
- [fzf](https://github.com/junegunn/fzf) — Fuzzy finder
- [gh](https://cli.github.com/) — GitHub CLI
