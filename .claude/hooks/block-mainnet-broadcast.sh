#!/usr/bin/env bash
# PreToolUse hook (Bash). A seat belt, not the barrier: the barrier is that keys live in a
# browser wallet or an encrypted keystore whose password never reaches Claude.
# This hook refuses commands that could sign, send, or expose a key, and FAILS CLOSED:
# any error inside it blocks the command (Claude Code only blocks on exit 2).
trap 'echo "BLOCKED: guard hook error, command refused" >&2; exit 2' ERR
set -euo pipefail
command -v jq >/dev/null || { echo "BLOCKED: jq missing, guard hook cannot run" >&2; exit 2; }

cmd="$(jq -er '.tool_input.command')"
deny() { echo "BLOCKED by .claude/hooks/block-mainnet-broadcast.sh: $1. Print the exact command for a human to run instead." >&2; exit 2; }
has() { grep -Eq -- "$1" <<<"$2"; }

# A plain commit whose message mentions a forbidden word is fine (no chaining, no substitution).
if has '^[[:space:]]*git[[:space:]]+commit[[:space:]]' "$cmd" && ! has '[;&|`]|\$\(' "$cmd"; then exit 0; fi

check() {
  local c="$1" where="$2"
  # Signing, sending, or unlocking keys, whatever the spelling.
  has '(^|[^[:alnum:]_-])--(broadcast|resume|ffi|password|password-file|private-key|private-keys|mnemonic|mnemonic-passphrase|ledger|trezor|aws|gcp)([^[:alnum:]_-]|$)' "$c" && deny "signing or broadcasting flag ($where)"
  has 'FOUNDRY_FFI|PRIVATE_KEY|MNEMONIC|ETH_PASSWORD|ETH_KEYSTORE' "$c" && deny "key or ffi variable ($where)"
  has '(^|[^[:alnum:]_])cast([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+(s|send|m|mktx|p|publish|w|wallet|erc20|erc20-token|rpc|create2|da|decode-account)([[:space:]]|$)' "$c" && deny "cast send/mktx/publish/wallet/erc20/rpc ($where)"
  has '\$\{?\(?[[:alnum:]_]+\)?\}?[[:space:]]+(s|send|m|mktx|p|publish|w|wallet|erc20|rpc|create|script)([[:space:]]|$)' "$c" && deny "command hidden behind a variable ($where)"
  has '(^|[^[:alnum:]_])forge[[:space:]]+create([[:space:]]|$)' "$c" && deny "forge create ($where)"
  has 'eth_send(Raw)?Transaction|eth_sign|personal_sign' "$c" && deny "raw RPC send or sign ($where)"
  # Mainnet CCTP, however quoted.
  has 'NETWORK[^[:alnum:]]{0,4}main' "$c" && deny "CCTP on mainnet ($where)"
  # Indirection that hides the real command.
  has '(bash|sh|zsh)[[:space:]]+-c|(^|[[:space:];&|])(eval|xargs|exec)[[:space:]]' "$c" && has 'cast|forge|node|tsx' "$c" && deny "indirect execution of cast/forge/node ($where)"
  # Secrets on disk.
  has '(^|[^[:alnum:]_.-])\.env(\.[[:alnum:]_-]+)?([^[:alnum:]_.-]|$)' "${c//.env.example/}" && deny ".env file ($where)"
  has 'keystores?/|UTC--|\.keystore|\.foundry/keystores' "$c" && deny "keystore ($where)"
  # History of a public repo.
  has 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push' "$c" && has '(^|[[:space:]])(-f|--force|--force-with-lease|--mirror|--delete|-d)([[:space:]=]|$)|[[:space:]]\+[[:alnum:]]|:[[:alnum:]]' "$c" && deny "destructive push ($where)"
  # --unlocked only against a local fork.
  has '--unlocked' "$c" && ! has '(127\.0\.0\.1|localhost)' "$c" && deny "--unlocked outside a local fork ($where)"
  return 0
}

check "$cmd" "command"

# Scripts from the repo run by the command: scan their content with the same rules.
# JS/TS scripts that shell out to cast are scanned for a "send" argument too.
for f in $(grep -Eo '[^[:space:]"'"'"']+\.(sh|ts|mjs|js|py)' <<<"$cmd" || true); do
  [[ -f "$f" ]] || continue
  body="$(cat -- "$f")"
  check "$body" "$f"
  has '"cast"|execFile|spawn' "$body" && has '"send"|'"'"'send'"'"'' "$body" && deny "script shells out to cast send ($f)"
done
exit 0
