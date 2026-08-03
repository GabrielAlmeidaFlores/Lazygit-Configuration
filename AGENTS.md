# AGENTS.md

Architectural patterns and coding standards for AI agents working on this codebase.

---

## Code Style & Conventions

### Comments

**ONLY documentation comments are allowed. NO inline comments.**

✅ **Allowed - Function Documentation:**
```bash
# function_name ARG1 ARG2
# Brief description of what the function does.
# Explains parameters, return values, side effects.
# Exit codes: 0 = success, 1 = failure, 130 = cancelled
function_name() {
  # implementation
}
```

❌ **NOT Allowed - Inline Comments:**
```bash
# Count total analyses
TOTAL=$(wc -l file)

# Launch in background
process &

# Wait for completion
wait $PID
```

**Rationale:** Code should be self-documenting. Inline comments clutter the code and often become outdated.

---

## Output & Printing Standards

### Core Principle

**ALL output must go through UI functions defined in `lib/ui.sh`.**

### Forbidden Commands

❌ **NEVER use directly in any file except `lib/ui.sh`:**
- `echo`
- `printf`

### Required Functions

✅ **Use these functions from `lib/ui.sh`:**

#### User Messages
```bash
ui_error "message"      # Error messages
ui_warning "message"    # Warning messages
ui_info "message"       # Info messages
ui_success "message"    # Success messages
ui_step "message"       # Progress indicators
ui_cancel               # Cancellation message
```

#### Technical Output
```bash
ui_print "string"       # Print with newline (replaces echo/printf '%s\n')
ui_print_raw "string"   # Print without newline (replaces echo -n/printf '%s')
```

#### UI Components
```bash
ui_header "title"
ui_panel "line1" "line2"
ui_section "title"
ui_content_box "title" "content"
ui_table_start / ui_table_row / ui_table_end
```

### Usage Examples

❌ **Wrong:**
```bash
echo "Processing..."
printf '%s\n' "$result"
echo "$data" | grep pattern
```

✅ **Correct:**
```bash
ui_step "Processing..."
ui_print "$result"
ui_print "$data" | grep pattern
```

### Function Return Values

For functions that return strings via stdout:

```bash
get_value() {
  local result="computed value"
  ui_print "$result"  # NOT echo or printf
}

VALUE=$(get_value)
```

---

## Architecture

### Directory Structure

```
commands/
├── lib/
│   ├── ui.sh                    # UI functions (ONLY file with echo/printf)
│   └── config.sh                # Config loader (reads settings.yaml via yq)
├── gateways/
│   ├── generative-ia.sh         # AI gateway (routes to providers)
│   └── adapters/
│       ├── copilot.sh           # GitHub Copilot adapter
│       ├── cursor.sh            # Cursor Agent adapter
│       └── _helpers.sh          # Shared adapter utilities
├── review_pr.sh                 # PR review with sequential analysis
├── gen_commit_with_ia.sh        # AI commit message generator
└── gen_branch_with_ia.sh        # AI branch name generator

settings.yaml                      # All AI prompts and configuration (replaces config.env)
config.state.yaml                # Runtime state: last used provider/model (gitignored)
config.state.yaml.example        # Template for config.state.yaml
config.yml                       # LazyGit UI configuration
state.yml                        # Auto-generated (gitignored)
```

### Gateway Pattern

**AI provider abstraction for easy swapping and testing.**

```
User Script → config_select_provider() → AI_PROVIDER set interactively
           → generative_ia() → Adapter (_generative_ia_copilot / _generative_ia_cursor)
```

#### Configuration (`settings.yaml` → `lib/config.sh`)
```bash
AI_PROVIDER="copilot"    # set at runtime via fzf picker; persisted in config.state.yaml
MODEL=""                 # Primary model
FALLBACK_MODEL=""        # Fallback on failure
MAX_RETRIES=2
TIMEOUT=60
```

#### Adding New Providers

1. Create `gateways/adapters/ia/provider.sh`
2. Implement `_generative_ia_provider()` function
3. Add case in `gateways/generative-ia.sh`
4. Add provider to `config_select_provider` list in `lib/config.sh`
5. Source UI functions: `source "$(dirname)/../../lib/ui.sh"`

---

## PR Review System

### 3-Pass Analysis Architecture

Each analysis type runs **three sequential passes**:

1. **Pass 1** - Initial analysis of the diff
2. **Pass 2** - Second analysis informed by Pass 1 findings
3. **Pass 3** - Validates combined issues, filters false positives

**Why 3 passes?**
- Increases accuracy
- Reduces false positives
- Provides multiple perspectives on the same code

### Sequential Execution

Analysis types run **sequentially**, one at a time. Each analysis is run to completion before the next begins, enabling cancellation between analyses and proper spinner feedback per pass.

### Available Analysis Types

```bash
Architecture        # SOLID, coupling, separation of concerns
Security           # Secrets, injection, auth bypasses
Code Quality       # Duplication, complexity, naming
Test Coverage      # Missing tests, edge cases
Performance        # N+1 queries, inefficient loops
Bugs               # Null dereferences, off-by-one, race conditions, logic errors
Fix Validation     # Validates fixes and auto-resolves GitHub comments
Spelling & Grammar # Typos, missing accents, language detection
```

### Data Flow

```
1. User selects PR → 2. Fetch diff + existing comments via gh → 3. Launch sequential analyses
                                                                        ↓
4. Each analysis runs 3 passes (with existing comments context) → 5. Write results to temp files
                                                                        ↓
6. Collect issues from files → 7. Generate comments → 8. Post to GitHub
```

**Existing Comments Integration:**
- Fetches inline comments via `gh api repos/{owner}/{repo}/pulls/{PR}/comments`
- Fetches general comments via `gh pr view --json comments`
- Passes to AI in all 3 passes with instruction: "DO NOT report issues already mentioned"
- Prevents duplicate issue reporting

### Result Storage

Each analysis writes to temp files (thread-safe):
```bash
$RESULTS_DIR/
├── Architecture.status     # "OK" | "ISSUES_FOUND" | "ERROR"
├── Architecture.issues     # One issue per line
├── Security.status
└── Security.issues
```

---

## Configuration Management

### ⚠️ CRITICAL RULE: ALL AI Prompts in `settings.yaml`

**MANDATORY: Every single AI prompt MUST be defined in `settings.yaml`.**

❌ **NEVER hardcode prompts in scripts:**
```bash
# WRONG - Hardcoded prompt
PROMPT="You are an AI assistant. Analyze this code..."
generative_ia "$PROMPT"
```

✅ **ALWAYS externalize in settings.yaml:**
```yaml
# settings.yaml
prompts:
  my_feature: |
    You are an AI assistant. Analyze this code...
```

```bash
# script.sh
PROMPT="$PROMPT_MY_FEATURE"
generative_ia "$PROMPT"
```

**Rationale:**
- ✅ Easy customization without touching code
- ✅ Version control of prompt evolution
- ✅ A/B testing different prompts
- ✅ User can override prompts
- ✅ Centralized prompt management

### Existing Prompt Templates

All AI prompts are **externalized** in `settings.yaml` under `prompts:`:

```yaml
prompts:
  analysis_pass1: |    # Pass 1 prompt
  analysis_pass2: |    # Pass 2 prompt
  analysis_pass3: |    # Pass 3 prompt
  comment: |           # GitHub comment generation
  commit: |            # Commit message generation
  branch: |            # Branch name generation
  instructions:
    architecture: |
    security: |
    ...
```

### Per-Analysis Instructions

```yaml
prompts:
  instructions:
    architecture: |
    security: |
    code_quality: |
    test_coverage: |
    performance: |
    spelling: |
```

### Template Placeholders

Use double-underscore notation:
```bash
__ANALYSIS_NAME__
__PR_TITLE__
__PR_AUTHOR__
__PR_BODY__
__PR_DIFF__
__INSTRUCTIONS__
```

Rendered via `render_template()` function.

---

## Error Handling

### Exit Codes

**Standard exit codes across all scripts:**

```bash
0   # Success
1   # General failure
130 # User cancellation (Ctrl+C)
```

### Cancellation Handling

All AI calls must handle user interruption:

```bash
_ai_cancel() {
  _CANCELLED=1
  [ -n "$_AI_PID" ] && kill "$_AI_PID" 2>/dev/null
  ui_cancel >&2
}
trap '_ai_cancel' INT

# Check cancellation
[ $_CANCELLED -eq 1 ] && return 130
```

### Retry Logic

AI providers implement retry with exponential backoff:

```bash
ATTEMPT=1
while [ $ATTEMPT -le $MAX_RETRIES ]; do
  # Try operation
  if [ $EXIT_CODE -eq 0 ]; then
    return 0
  fi
  
  ui_warning "Call failed, attempt $ATTEMPT/$MAX_RETRIES" >&2
  ATTEMPT=$((ATTEMPT + 1))
  sleep $((2 ** (ATTEMPT - 1)))  # Exponential backoff
done
```

---

## Git Integration

### GitHub CLI (`gh`)

**All GitHub operations use `gh` CLI with PAT resolution:**

```bash
# Resolve PAT from:
# 1. Remote URL (https://TOKEN@github.com/...)
# 2. git config --local github.user
# 3. Default gh auth

gh_run() {
  if [ -n "$_GH_PAT" ]; then
    GH_TOKEN="$_GH_PAT" gh "$@"
  else
    gh "$@"
  fi
}
```

### Commit Messages

Generated via AI with human-in-the-loop review:

```bash
1. Collect staged diff
2. Generate commit message via AI
3. Present for review
4. Allow editing before commit
```

### Branch Names

Convention-based generation:
```
feat/feature-description
fix/bug-description
chore/task-description
refactor/refactor-description
```

---

## Testing & Validation

### Syntax Validation

**Always validate bash syntax after changes:**

```bash
bash -n script.sh
```

### No Emojis in Generated Content

❌ **Never add emojis to AI-generated output** (commit messages, branch names, PR comments)

✅ **Emojis are allowed only in UI layer** (`lib/ui.sh` functions and `ui_header` calls)

### Emoji Color Rule

**Only use 4-byte UTF-8 emojis (U+1F000 and above). Never use 3-byte emoji characters that may render as monochrome.**

✅ **Always colored (4-byte UTF-8, U+1F000+):**
```
🔍 🔒 💎 🧪 🚀 🐛 🔧 📝 🏗️ 🛠️ 🕐 🔄 📝 🌿
```

❌ **May render monochrome (3-byte UTF-8, avoid):**
```
⚡ ⚙️ ⏳ ✍️ ☁️ ♻️  (these are in U+2000-U+2FFF range)
```

**How to verify:** An emoji is safe if its first UTF-8 byte is `F0` (4-byte sequence).
```bash
printf '%s' "🚀" | od -A n -t x1 | head -1  # shows: f0 9f 9a 80  ← safe
printf '%s' "⚡" | od -A n -t x1 | head -1  # shows: e2 9a a1     ← avoid
```

### File State Management

**`state.yml` is gitignored:**
- Auto-generated by LazyGit
- Contains machine-specific data
- Template provided: `state.yml.example`

---

## Adding New Features

### New Analysis Type

1. Add to `settings.yaml`:
   ```yaml
   prompts:
     instructions:
       newtype: |
         Check for: ...
   ```

2. Add to analysis menu in `review_pr.sh`:
   ```bash
   ANALYSES_RAW=$(ui_print "Architecture
   Security
   ...
   New Type  ← Add here
   All" | fzf ...)
   ```

3. Add to "All" list:
   ```bash
   if ui_print "$ANALYSES_RAW" | grep -q "^All$"; then
     ANALYSES_RAW="Architecture
     ...
     New Type"  ← Add here
   fi
   ```

4. Add case in `get_instructions()`:
   ```bash
   "New Type") ui_print "${PROMPT_INSTRUCTIONS_NEWTYPE:-Default instructions}" ;;
   ```

### New AI Provider

1. Create `gateways/adapters/ia/newprovider.sh`
2. Implement `_generative_ia_newprovider()` with:
   - Retry logic
   - Timeout handling
   - Cancellation support
   - Error messages via UI functions
   - **ALL prompts from `settings.yaml`** (no hardcoded prompts)
3. Add to `gateways/generative-ia.sh` switch
4. Document in `README.md`

### New AI Feature

**When adding ANY feature that uses AI:**

1. **Add prompt to `settings.yaml`:**
   ```yaml
   prompts:
     new_feature: |
       Your AI instruction here...
   ```

2. **Use in script:**
   ```bash
   PROMPT="$PROMPT_NEW_FEATURE"
   RESPONSE=$(generative_ia "$PROMPT" "$VERBOSE")
   ```

3. **NEVER write prompts directly in the script code**

---

## Best Practices

### Function Naming

```bash
public_function()      # No prefix, exported
_private_function()    # Underscore prefix, internal
```

### Variable Naming

```bash
GLOBAL_VAR="value"     # UPPERCASE for globals
local_var="value"      # lowercase for locals
_INTERNAL="value"      # Underscore prefix for internal
```

### Subshells & Background Jobs

When running in parallel, remember:
- **Subshells don't share array modifications with parent**
- Use temp files for communication
- Always collect exit codes with `wait`

```bash
# Wrong - array modifications lost
(run_task) &
PIDS+=($!)

# Correct - write to file
(run_task > "$TEMP_FILE") &
PIDS+=($!)
wait $pid
result=$(cat "$TEMP_FILE")
```

### Dependencies

**All external commands must be checked:**

```bash
for dep in gh fzf jq; do
  if ! command -v "$dep" &>/dev/null; then
    ui_error "'$dep' not found. Please install it."
    exit 1
  fi
done
```

---

## Performance Considerations

### Parallelization

- ✅ Parallelize **independent** operations
- ❌ Don't parallelize **dependent** operations
- Use background jobs (`&`) + `wait` for bash-native parallelization

### AI Call Optimization

- Use `VERBOSE=0` for non-interactive AI calls
- Implement timeouts to prevent hanging
- Cache results when appropriate
- Limit diff size to ~400 lines

### File Operations

- Use temp files for large data
- Clean up with `trap` on EXIT
- Avoid multiple reads of the same file

---

## Security

### Secrets Management

- ✅ Never commit secrets
- ✅ Use git config for PATs
- ✅ Check for secrets in PR review
- ❌ Don't log sensitive data

### Input Validation

- Validate all user inputs
- Sanitize data before shell execution
- Use `jq` for JSON parsing (not `eval`)

---

## Documentation

### Required Documentation

**Every public function must have:**

```bash
# function_name ARG1 ARG2
# Brief description of what this function does.
# More detailed explanation if needed.
# Exit codes: 0 = success, 1 = failure, 130 = cancelled
function_name() {
  ...
}
```

### README Updates

When adding features, update:
- Feature list
- Usage examples
- Configuration options
- Troubleshooting section

---

## Summary

**Golden Rules:**
1. ✅ Use ONLY UI functions for output (`ui_*` from `lib/ui.sh`)
2. ✅ Documentation comments only (NO inline comments)
3. ✅ ALL AI prompts MUST be in `settings.yaml` (NEVER hardcoded)
4. ✅ Always validate bash syntax (`bash -n script.sh`)
5. ✅ Handle cancellation (exit 130)
6. ✅ Parallelize independent operations when possible
7. ✅ Only use 4-byte UTF-8 emojis (U+1F000+) in UI layer — never 3-byte (monochrome risk)
8. ✅ Follow exit code conventions (0, 1, 130)

**When in doubt:**
- Check existing code patterns
- Use UI functions from `lib/ui.sh`
- Put ALL prompts in `settings.yaml`
- Test with `bash -n`
- Document your changes

**Before committing, verify:**
```bash
# No hardcoded prompts in scripts
grep -r "generative_ia" commands/ | grep -v "settings.yaml" | grep '".*You are'

# No echo/printf outside ui.sh
grep -r "echo\|printf" commands/ --exclude-dir=lib | grep -v "ui.sh"

# Syntax is valid
bash -n commands/**/*.sh
```

---

*Last updated: 2026-07-30*
