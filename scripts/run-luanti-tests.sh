#!/usr/bin/env bash
# run-luanti-tests.sh
# Universal test runner helper for Luanti TestKit.
# Checks server status and runs tests via server console.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTAINER_NAME="${CONTAINER_NAME:-luanti-aliveworld}"
test_spec="${1:-all}"
player="${2:-}"

echo "=============================================="
echo " Luanti TestKit - Test Runner"
echo "=============================================="
echo ""

# === Check Docker ===
if ! command -v docker &>/dev/null; then
    echo "ERROR: docker not found. Install Docker first."
    exit 1
fi

# === Check server ===
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "ERROR: Container '$CONTAINER_NAME' is not running."
    echo ""
    echo "Start the server first:"
    echo "  cd $ROOT"
    echo "  docker compose up -d"
    echo ""
    echo "Then wait for it to be ready:"
    echo "  docker logs -f $CONTAINER_NAME"
    echo ""
    echo "Create test player on the server console:"
    echo "  docker attach $CONTAINER_NAME"
    echo "  Then: /setpassword awbot"
    echo "  Then: /grant awbot all"
    echo "  Exit attach with Ctrl+P Ctrl+Q (NOT Ctrl+C)"
    exit 1
fi

echo "Server container '$CONTAINER_NAME' is running."
echo ""

# === Build command ===
if [ "$test_spec" = "all" ]; then
    CMD="/ltk_all"
else
    CMD="/ltk_run $test_spec"
fi
if [ -n "$player" ]; then
    CMD="$CMD $player"
fi

echo "Command to run on server: $CMD"
echo ""
echo "=============================================="
echo " OPTION A: Interactive (recommended)"
echo "=============================================="
echo ""
echo "1. Attach to server console:"
echo "   docker attach $CONTAINER_NAME"
echo ""
echo "2. Make sure test client is connected:"
echo "   ./scripts/run-test-client.sh"
echo ""
echo "3. Run tests:"
echo "   $CMD"
echo ""
echo "4. Check results in server console output."
echo ""
echo "5. Exit attach: Ctrl+P Ctrl+Q"
echo ""
echo "=============================================="
echo " OPTION B: Quick inject (via docker exec)"
echo "=============================================="
echo ""
echo "   echo \"$CMD\" | docker attach $CONTAINER_NAME"
echo ""
echo "   WARNING: This is unreliable for interactive commands."
echo "   Use Option A for reliable results."
echo ""
echo "=============================================="
echo " OPTION C: Check recent test output in logs"
echo "=============================================="
echo ""
echo "   docker logs $CONTAINER_NAME --tail 50 | grep '\[luanti_testkit\]'"
echo ""
echo "=============================================="

# Print recent test output if any
echo "Recent test output from server logs:"
echo "---"
docker logs "$CONTAINER_NAME" --tail 30 2>/dev/null | grep '\[luanti_testkit\]' || echo "(no test output found in recent logs)"
echo "---"
