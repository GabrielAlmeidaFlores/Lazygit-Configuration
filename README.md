# LazyGit Enhanced Configuration

A powerful LazyGit configuration with automated workflows, intelligent tooling, and beautiful theme integration.

## Features

### Automation & Intelligence

- **AI-Powered Commit Messages** - Generate professional, conventional commit messages with gitmoji
- **AI-Powered Branch Names** - Generate descriptive branch names with automatic emoji prefixes
- **AI Thinking Output** - See the AI reasoning process in real-time as it generates results
- **Configurable AI Model** - Easily switch between GPT, Claude, and Gemini models via `config.env`

### User Experience

- **Human-in-the-Loop** - Review and edit all suggestions before applying
- **Interactive Editing** - Integrated editor support (nano, vim, etc.)
- **Optional Context Input** - Provide additional context to the AI for better results
- **English Standardization** - Consistent English-only output for international teams

### Customization

- **Dracula Theme** - Complete color scheme integration
- **Modular Architecture** - Easy to extend and customize
- **Gateway Pattern** - Swap AI providers or add new integrations effortlessly

## Prerequisites

- [LazyGit](https://github.com/jesseduffield/lazygit) - Terminal UI for git
- Git - Version control system
- Bash - Shell scripting
- Text editor - nano, vim, or your preferred editor

### Optional (for AI features)

- [GitHub Copilot CLI](https://www.npmjs.com/package/@github/copilot) - AI provider (or use alternative)

## Installation

1. Clone or copy this configuration to your LazyGit config directory:

   ```bash
   ~/.config/lazygit/
   ```

2. Make scripts executable:

   ```bash
   chmod +x ~/.config/lazygit/commands/*.sh
   chmod +x ~/.config/lazygit/commands/gateways/*.sh
   ```

3. **(Optional)** For AI features, install and authenticate GitHub Copilot CLI:

   ```bash
   npm install -g @github/copilot
   copilot auth
   ```

   Or configure a different AI provider in `commands/gateways/generative-ia.sh`

## Quick Start

### Using Custom Commands

The configuration provides keyboard shortcuts for common workflows:

| Key | Context | Action                  |
| --- | ------- | ----------------------- |
| `C` | Files   | Generate commit message |
| `B` | Files   | Generate branch name    |

Simply stage your changes and press the corresponding key!

## Standards & Conventions

### Commit Message Format

```
<gitmoji> <type>(<scope>): <summary>

- <Detailed Bullet Points>
```

### Type Mapping

| Type     | Emoji | Description               |
| -------- | ----- | ------------------------- |
| feat     | ✨    | New logic/functionality   |
| fix      | 🐛    | Bug fixes                 |
| refactor | ♻️    | Code refactoring/cleaning |
| chore    | 🔧    | Build/Config/CI/Docker    |
| docs     | 📝    | Documentation/Comments    |
| style    | 💄    | CSS/Styling/UI            |

## Branch Name Format

```
<emoji><type>/<descriptive-name>
```

Example: `🐛fix/auth-token-validation`

### Branch Prefix Mapping

| Prefix    | Emoji | Description                     |
| --------- | ----- | ------------------------------- |
| fix/      | 🐛    | Bug fixes and corrections       |
| feat/     | ✨    | New features and modules        |
| chore/    | 🔨    | Config, deps, docker, CI, build |
| refactor/ | ♻️    | Code structure changes          |
| docs/     | 📝    | Documentation and markdown      |
| style/    | 💄    | CSS/Styling/UI changes          |
| test/     | ✅    | Test additions/modifications    |
| perf/     | ⚡    | Performance improvements        |

## File Structure

```
~/.config/lazygit/
├── commands/
│   ├── gateways/
│   │   └── generative-ia.sh      # AI service gateway (modular)
│   ├── gen_commit_with_ia.sh     # Commit message generator
│   └── gen_branch_with_ia.sh     # Branch name generator
├── config.env                    # AI configuration (model, retries, timeout)
├── config.yml                    # LazyGit configuration & theme
└── README.md                     # Documentation
```

## Available Commands

### AI-Powered Workflows

#### Generate Commit Message (`C`)

1. Stage your changes in LazyGit
2. Press `C` in the files view
3. **(Optional)** Provide additional context to help the AI understand your changes
   - Press `[Enter]` to skip if no context is needed
   - Example context: "Refactoring for better performance" or "Part of authentication redesign"
4. Review the generated message
5. Press `[Enter]` to commit or `[e]` to edit

#### Generate Branch Name (`B`)

1. Stage your changes in LazyGit
2. Press `B` in the files view
3. **(Optional)** Provide additional context to help the AI categorize your changes
   - Press `[Enter]` to skip if no context is needed
   - Example context: "Working on user authentication" or "Fixing payment bug"
4. Review the generated name with emoji
5. Press `[Enter]` to create branch or `[e]` to edit

## Configuration

### AI Model & Behavior

All AI settings are configured in `config.env` at the project root:

```bash
# config.env
MODEL="gpt-4.1"   # Change model here
MAX_RETRIES=2
TIMEOUT=30
```

Available models:

| Provider | Models |
| -------- | ------ |
| GPT      | `gpt-4.1`, `gpt-5-mini`, `gpt-5.1`, `gpt-5.1-codex`, `gpt-5.1-codex-mini`, `gpt-5.2`, `gpt-5.3-codex` |
| Claude   | `claude-haiku-4.5`, `claude-sonnet-4.5`, `claude-sonnet-4.6`, `claude-opus-4.5`, `claude-opus-4.6` |
| Gemini   | `gemini-3-pro-preview` |

### Adding Custom Commands

Edit `config.yml` to add new commands:

```yaml
customCommands:
  - key: "C"
    context: "files"
    description: "Generate commit message"
    command: "bash ~/.config/lazygit/commands/gen_commit_with_ia.sh"
    output: terminal
  - key: "B"
    context: "files"
    description: "Generate branch name"
    command: "bash ~/.config/lazygit/commands/gen_branch_with_ia.sh"
    output: terminal
```

### Theme Customization

The configuration includes a complete Dracula theme. Modify colors in `config.yml`:

```yaml
gui:
  theme:
    activeBorderColor: ["#bd93f9", "bold"]
    stagedChangesColor: ["#50fa7b"]
    unstagedChangesColor: ["#ff5555"]
    # ... more theme options
```

See `config.yml` for complete theme definitions.

## Extending & Customizing

### Adding New Features

The modular architecture makes it easy to add new commands:

1. Create a new script in the `commands/` directory (e.g., `commands/gen_something.sh`)
2. Source any gateways you need: `source "$SCRIPT_DIR/gateways/generative-ia.sh"`
3. Implement your logic
4. Add a custom command in `config.yml`

### Using Different AI Providers

Edit `commands/gateways/generative-ia.sh` to use any AI service:

```bash
# Example: Switch to OpenAI CLI
COPILOT_BIN="/usr/local/bin/openai"

# Or use a different service entirely
AI_SERVICE_BIN="/path/to/your/ai/cli"
```

You can also create additional gateways for different services.

### Customizing Prompts

Each generator script has a `PROMPT` variable you can customize:

**For commit messages** - Edit `commands/gen_commit_with_ia.sh`:

```bash
PROMPT="Your custom instructions here..."
```

**For branch names** - Edit `commands/gen_branch_with_ia.sh`:

```bash
PROMPT="Your custom instructions here..."
```

### Adjusting Behavior

Modify settings in `config.env` at the project root:

```bash
MODEL="gpt-4.1"  # AI model to use
MAX_RETRIES=2    # Number of retry attempts
TIMEOUT=30       # Request timeout in seconds
```

## Troubleshooting

### Common Issues

**AI features not working**

- Verify your AI provider is installed and authenticated
- Check the binary path in `commands/gateways/generative-ia.sh`
- Check your model setting in `config.env`
- Test directly: `./commands/gateways/generative-ia.sh "test prompt"`

**No staged changes error**

- Ensure you have staged changes before running commands
- Stage files in LazyGit with `[Space]`

**Editor not opening**

- Set your preferred editor: `export EDITOR=nano`
- Add to `~/.bashrc` or `~/.zshrc` to make permanent

**Permission denied**

- Make scripts executable: `chmod +x ~/.config/lazygit/commands/**/*.sh`

## Examples

### Commit Message Generation

**Scenario:** Staged changes adding JWT authentication

**Generated Output:**

```
✨ feat(auth): implement JWT token validation

- Add token verification middleware
- Implement expiration checking logic
- Add error handling for invalid tokens
```

**With User Context:**

If you provide context like: `"Part of security enhancement for API endpoints"`

The AI will consider this additional information when generating the commit message, potentially providing more detailed explanations about the security improvements.

### Branch Name Generation

**Scenario:** Staged changes fixing a bug in authentication

**Generated Output:**

```
🐛fix/auth-token-validation
```

**With User Context:**

If you provide context like: `"Fixing token expiration issue from bug report #123"`

The AI will better understand this is a fix (not a feature) and might suggest a more specific name like: `🐛fix/token-expiration-validation`

## Tips for Using Context

### When to Provide Context

- **Complex changes** - When the diff alone might not explain the full picture
- **Multi-purpose changes** - When changes serve a specific goal not obvious from code
- **Bug fixes** - Reference issue numbers or describe the problem being solved
- **Refactoring** - Explain the reason for restructuring (e.g., "performance optimization")
- **Part of larger feature** - Mention the overall feature being worked on

### Context Examples

Good context inputs:
- `"Part of user authentication redesign"`
- `"Fixing memory leak reported in production"`
- `"Refactoring for better testability"`
- `"Implementing requirements from ticket #456"`
- `"Performance optimization for large datasets"`

Less helpful context:
- `"Update code"` (too vague)
- `"Fix bug"` (AI can infer this from the diff)
- Very long explanations (keep it concise)

## Contributing

This configuration is designed to be extended. Feel free to:

- Add new custom commands
- Create additional gateways for different services
- Improve existing scripts
- Share your enhancements

## License

This configuration is free to use and modify.

## Credits

- [LazyGit](https://github.com/jesseduffield/lazygit) - Amazing terminal UI for git
- [Dracula Theme](https://draculatheme.com/) - Beautiful color scheme
- [Conventional Commits](https://www.conventionalcommits.org/) - Commit message standard
- [Gitmoji](https://gitmoji.dev/) - Emoji guide for commit messages
