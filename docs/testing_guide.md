# RSD Test Execution & Integration Guide

This guide establishes the protocols, execution patterns, and coverage requirements for testing the **RSD** (Rapid Script Developer) framework.

---

## 1. Test Environment Setup

RSD tests are built using **Bats-core** (Bash Automated Testing System) and measured with **Kcov** for code coverage.

### Option A: For Native / Local Users (Arch Linux Native Setup)
Since your workstation runs Native Arch Linux, you can run all tests and coverage checks locally without the performance overhead of containers:

```bash
# 1. Install Bats-core and standard helper extensions
sudo pacman -S bats bats-support bats-assert

# 2. Install Kcov for code coverage tracing
sudo pacman -S kcov
```

### Option B: For Docker / Standard Standardized Environments (CI & Team Setup)
For automated pipelines or team members using isolated environments, run tests within the project's standardized container boundary:

```bash
# 1. Build the testing container
docker build -t rsd-test-runner -f Dockerfile.test .

# 2. Run the full test suite in an isolated container
docker run --rm -v "$(pwd):/workspace" -w /workspace rsd-test-runner bats tests/
```

---

## 2. Directory Layout & Structure

All tests are mapped explicitly to verify the core engine and libraries under the `tests/` directory:

```
tests/
├── unit/                   # Pure function & library testing
│   ├── bash_extensions.bats
│   └── gpg_lib.bats
├── integration/            # CLI Command Routing & Sandbox testing
│   ├── rsd_cli.bats
│   └── gpg_integration.bats
└── test_helper/            # Sourced Bats utility setup files
    └── helper.bash
```

---

## 3. Test Execution Command Set

### 3.1 Run the Entire Test Suite
Executes all unit and integration test specs:
```bash
bats tests/
```

### 3.2 Run a Specific Test Category or File
Run only unit tests:
```bash
bats tests/unit/
```

Run a specific file:
```bash
bats tests/unit/bash_extensions.bats
```

### 3.3 Output Formatters
Use the `pretty` formatter for high-density terminal color results:
```bash
bats -F pretty tests/
```

---

## 4. Measuring Code Coverage (Kcov)

**Kcov** tracks line execution at the OS level using `ptrace` system calls. It requires **no modifications** to your code and does not pollute your environment.

### 4.1 Execute Tests with Coverage Gathering
Run the test runner wrapped in the Kcov daemon:
```bash
# Clean previous coverage logs
rm -rf coverage

# Trace execution of bats tests across core directories
kcov \
  --include-path=$(pwd)/lib,$(pwd)/command,$(pwd)/rsd \
  $(pwd)/coverage \
  bats tests/
```

### 4.2 View Coverage Reports
Once execution completes:
1. Open the interactive HTML coverage page:
   ```bash
   xdg-open coverage/index.html
   ```
2. For CI integration, Kcov generates a standardized XML format at:
   ```
   coverage/cobertura.xml
   ```

---

## 5. Mocking Protocols in RSD

To prevent tests from leaking state, polluting files, or modifying personal credentials, follow these two strict mocking boundaries:

### Boundary 1: Keyring & SSH Sandboxing (Real Binary Integration)
When writing integration tests that rely on active host system binaries (e.g. `gpg`), isolate process states by mapping temporary directories to environment variables:

```bash
setup() {
    # Isolate local directories
    TEST_SANDBOX_DIR=$(mktemp -d -t rsd-sandbox.XXXXXX)
    export HOME="$TEST_SANDBOX_DIR"
    
    # Isolate GPG Ring
    export GNUPGHOME="${TEST_SANDBOX_DIR}/.gnupg"
    mkdir -p -m 700 "$GNUPGHOME"
}
```

### Boundary 2: Inline Function Redefinitions (Unit Mocks)
For external APIs, downloads, or dependencies (like `wget` or `git`), declare an inline Bash function *before* sourcing the target script to intercept calls:

```bash
# Intercept repository checks by mocking wget version downloads
wget() {
    echo "RSD_VERSION='1.9.12'"
    return 0
}
export -f wget
```

---

## 6. Exit Code Diagnostic Compliance

All integration assertions must explicitly validate that command returns align with [AGENTS.md System Exit Codes](file:///home/raul/Devel/rsd/AGENTS.md#6-exit-code-diagnostic-conformity):

* **SUCCESS (`0`)**: Assert standard successful CLI route outputs.
* **Bad Usage (`2`)**: Assert incorrect action strings or missing mandatory parameters return `2`.
* **Program Not Found (`3`)**: Assert early failure when dependencies are absent from `$PATH` return `3`.
* **Direct Execution Block (`12`)**: Assert sourcing libraries directly outside of `rsd` return `12`.
