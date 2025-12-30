# Checks that TODO comments have corresponding issues.
todo-checker:
  ./ops/scripts/todo-checker.sh

# Runs semgrep on the entire monorepo.
semgrep:
  semgrep scan --config .semgrep/rules/ --error .

# Runs semgrep tests.
semgrep-test:
  semgrep scan --test --config .semgrep/rules/ .semgrep/tests/

# Runs shellcheck.
shellcheck:
  find . -type f -name '*.sh' -not -path '*/node_modules/*' -not -path './packages/contracts-bedrock/lib/*' -not -path './packages/contracts-bedrock/kout*/*' -exec sh -c 'echo "Checking $1"; shellcheck "$1"' _ {} \;

# Generates a table of contents for the README.md file.
toc:
  md_toc -p github README.md

# Builds the forge artifacts required for devnet-allocs.
forge-build:
  cd packages/contracts-bedrock && forge build

# Generates devnet allocs files in .devnet directory.
# This creates L1/L2 allocs, addresses, and deploy config for e2e testing.
devnet-allocs: forge-build
  go run ./op-chain-ops/cmd/devnet-allocs

# Generates devnet allocs with custom output directory.
devnet-allocs-outdir outdir: forge-build
  go run ./op-chain-ops/cmd/devnet-allocs --outdir={{outdir}}

# Starts L1 only with devnet allocs.
devnet-l1:
  ./ops/scripts/devnet/start-l1.sh

# Generates L2 genesis from devnet allocs (requires L1 running).
devnet-l2-genesis:
  ./ops/scripts/devnet/generate-l2-genesis.sh

# Starts full devnet environment (L1 + L2).
devnet-up: devnet-allocs
  ./ops/scripts/devnet/start-devnet.sh

# Stops devnet and cleans up.
devnet-down:
  @echo "Stopping devnet..."
  @pkill -f "anvil.*--chain-id 900" || true
  @pkill -f "op-geth.*--networkid 901" || true
  @rm -rf .devnet/data
  @echo "Devnet stopped."

# Cleans all devnet files.
devnet-clean:
  rm -rf .devnet
