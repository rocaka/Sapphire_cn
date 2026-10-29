#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-text-input.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Stubs/PublicTextInputPolicy.swift" "$ROOT/scripts/TextInputPolicyProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
xcrun swiftc -typecheck -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/scripts/TextInputTypecheckFixtures.swift" "$ROOT/Sapphire/System/EventMonitorHub.swift" \
  "$ROOT/Sapphire/Stubs/PublicTextInputPolicy.swift" "$ROOT/Sapphire/Stubs/PublicSnippetManager.swift" \
  "$ROOT/Sapphire/Stubs/PublicFinderCutPaste.swift" "$ROOT/Sapphire/Stubs/PublicTextInputStatusView.swift"
