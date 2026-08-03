# Tests

Unit tests for the AI-powered Lazygit commands using [bats-core](https://github.com/bats-core/bats-core).

## Setup

```bash
brew install bats-core
```

## Running

```bash
# All tests
bats tests/

# Single file
bats tests/test_render_template.bats

# Verbose output
bats --verbose-run tests/
```

## Structure

```
tests/
├── helpers/
│   ├── fixture.bash      # Minimal settings.yaml fixture for tests that source lib/config.sh
│   ├── mock_fzf.bash     # fzf stub — set MOCK_FZF_OUTPUT before calling fzf-using functions
│   └── mock_yq.bash      # yq stub — set MOCK_YQ_OUTPUT before calling yq-using functions
├── test_cfg_str.bats         # _cfg_str: strips yq's "" artifact for empty strings
├── test_cfg_validate.bats    # _cfg_validate: rejects invalid provider, types, empty prompts
├── test_config_state.bats    # config_select_provider: state file lifecycle and cancellation
├── test_render_template.bats # render_template: placeholder replacement
└── README.md
```

## Writing new tests

Use the helpers to isolate external dependencies:

```bash
setup() {
  load helpers/mock_yq      # overrides yq binary
  load helpers/mock_fzf     # overrides fzf binary
  load helpers/fixture      # provides setup_config_fixture / teardown_fixture

  export _CONFIG_FILE="$(mktemp)"
  setup_config_fixture "$_CONFIG_FILE"

  source "$REPO_ROOT/commands/lib/ui.sh"
  source "$REPO_ROOT/commands/lib/config.sh"
}
```

Control mock outputs:

```bash
MOCK_YQ_OUTPUT="copilot"   # what yq returns
MOCK_YQ_EXIT=0             # exit code for yq (0 = success)
MOCK_FZF_OUTPUT="cursor"   # what fzf returns (simulates user selection)
MOCK_FZF_EXIT=0            # 0 = selected, 130 = cancelled (Ctrl+C)
```
