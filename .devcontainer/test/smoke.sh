#!/usr/bin/env bash
# The Try Weik.io container's smoke test, run inside the container as its developer's user once the platform is ready:
#   bash /usr/local/share/weikio-dev/smoke.sh [<folder to create the integration in>]
# Every step prints its command and output and ends with PASS or FAIL, and the exit code is the number of failures.
set -uo pipefail

work="${1:-$PWD}"
name="${SMOKE_INTEGRATION:-hello}"
D="${WEIKIO_DEV_DATA:-/home/weikio/.weikio-dev}"
out="$(mktemp -d)"
failures=0

section() { printf '\n== %s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }
show() { printf '$ %s\n' "$*"; "$@" 2>&1 | tee "$out/last"; return "${PIPESTATUS[0]}"; }

# Waits until the file holds the text, at most the given seconds, and no longer than the process writing it runs.
wait_for_text() {
    local file="$1" text="$2" timeout="$3" pid="$4" started=$SECONDS
    until grep -q -F -- "$text" "$file" 2>/dev/null; do
        (( SECONDS - started >= timeout )) && return 1
        kill -0 "$pid" 2>/dev/null || { grep -q -F -- "$text" "$file" 2>/dev/null; return; }
        sleep 2
    done
}

section "versions: the Weik.io CLI and the platform are one release"
show weikio version
client="$(sed -n '1s/^weikio \([^ ]*\).*/\1/p' "$out/last")"
server="$(grep -i -m1 -E '^(server|platform)' "$out/last" | grep -o -E '[0-9]{4}\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?' | head -n 1)"
if [ -n "$client" ] && [ "$client" = "$server" ]; then pass "CLI $client = server $server"; else fail "CLI '$client' and server '$server' differ or are missing"; fi

section "the Weik.io CLI is signed in"
if show weikio whoami; then pass "weikio whoami"; else fail "weikio whoami"; fi

section "every process of the platform is up"
if show weikio-dev status; then pass "weikio-dev status: all up, all checks ok"; else fail "weikio-dev status"; fi

section "the admin signs in with a password alone: the installation asks for no authenticator app"
weikio settings get -o json > "$out/settings" 2>&1
required="$(jq -r '[.. | objects | select(has("twoFactorRequired")) | .twoFactorRequired] | first' "$out/settings" 2>/dev/null)"
if [ "$required" = false ]; then pass "twoFactorRequired is false"; else fail "twoFactorRequired is '$required'"; cat "$out/settings"; fi

section "agent dev is online in devtest"
show weikio get agents --env devtest
if grep -E '(^|[[:space:]])dev([[:space:]]|$)' "$out/last" | grep -q -i -E 'online|true|yes'; then pass "agent dev online"; else fail "agent dev is not listed online"; fi

section "weikio init $name"
cd "$work" || exit 99
rm -rf "./$name"
if show weikio init "$name" && [ -d "./$name" ]; then pass "init wrote ./$name"; else fail "weikio init $name"; fi
message="$(sed -n 's/^message[[:space:]]*=[[:space:]]*//p' "./$name/application.properties" 2>/dev/null | head -n 1)"
[ -n "$message" ] || message="$name"
echo "the route logs: $message"

section "weikio run $name: publish, deploy to devtest and follow its log lines"
echo "\$ weikio run $name"
started=$SECONDS
weikio run "$name" > "$out/run" 2>&1 &
run_pid=$!
if wait_for_text "$out/run" "$message" 600 "$run_pid"; then
    pass "a log line of the deployed route reached the CLI after $(( SECONDS - started )) s"
else
    fail "no log line of the deployed route within 600 s"
fi
kill -INT "$run_pid" 2>/dev/null
sleep 2
kill "$run_pid" 2>/dev/null
cat "$out/run"

section "weikio status sandbox/$name"
if show weikio status "sandbox/$name" && grep -q -i running "$out/last"; then pass "deployment Running"; else fail "deployment not Running"; fi

section "weikio logs sandbox/$name"
if show weikio logs "sandbox/$name" --since 15m --limit 10 && grep -q -F -- "$message" "$out/last"; then pass "log lines read back"; else fail "no log lines read back"; fi

section "weikio dev run $name: run it locally with Camel"
echo "\$ weikio dev run $name"
started=$SECONDS
weikio dev run "$name" > "$out/devrun" 2>&1 &
dev_pid=$!
if wait_for_text "$out/devrun" "$message" 600 "$dev_pid"; then
    pass "Camel ran the route locally after $(( SECONDS - started )) s"
else
    fail "Camel printed no log line of the route within 600 s"
fi
kill -INT "$dev_pid" 2>/dev/null
sleep 5
kill "$dev_pid" 2>/dev/null
pkill -INT -f 'camel.*run' 2>/dev/null
tail -n 25 "$out/devrun"

section "the admin UI is served on http://localhost:8580"
if curl -fsS http://localhost:8580/ -o "$out/ui.html" && grep -q -i '<div id="root"\|<html' "$out/ui.html"; then
    pass "GET / returned the admin UI page ($(wc -c < "$out/ui.html") bytes): $(grep -o -i '<title>[^<]*</title>' "$out/ui.html" | head -n 1)"
else
    fail "GET / did not return the admin UI page"
fi

section "weikio-dev ui-link prints a set-password link"
if weikio-dev ui-link > "$out/link" 2>&1 && grep -q 'http://localhost:8580/' "$out/link"; then
    pass "a one-time link was issued (not printed here)"
else
    fail "weikio-dev ui-link"; cat "$out/link"
fi
link_now="$(grep -o 'http://localhost:8580/[^ ]*' "$out/link" | head -n 1)"

section "the shown-once values are in no log and no command line"
key="$(sed -n 's/^WEIKIO_DEV_ADMIN_KEY=//p' "$D/secrets/admin.env")"
first_link="$(sed -n 's/^WEIKIO_DEV_FIRST_UI_LINK=//p' "$D/secrets/admin.env")"
leaks=0
for value in "$key" "$first_link" "$link_now"; do
    [ -n "$value" ] || continue
    if grep -r -l -F -- "$value" "$D/logs" 2>/dev/null; then leaks=$((leaks + 1)); fi
    if ps -eo args | grep -v grep | grep -q -F -- "$value"; then leaks=$((leaks + 1)); echo "on a command line"; fi
done
[ "$(stat -c %a "$D/secrets/admin.env")" = 600 ] || { leaks=$((leaks + 1)); echo "admin.env is not 0600"; }
[ "$(stat -c %a "$D/secrets")" = 700 ] || { leaks=$((leaks + 1)); echo "the secrets folder is not 0700"; }
if [ "$leaks" = 0 ] && [ -n "$key" ]; then pass "key and links: in no log, on no command line; admin.env 0600"; else fail "$leaks leaks"; fi

section "listeners: only 127.0.0.1"
ss -ltnH | awk '{print $4}' | sort -u | tee "$out/listen"
if grep -v -E '^(127\.0\.0\.1|\[::1\]|\[::ffff:127\.0\.0\.1\]):' "$out/listen" | grep -q .; then
    fail "something listens beyond the loopback address: $(grep -v -E '^(127\.0\.0\.1|\[::1\]|\[::ffff:127\.0\.0\.1\]):' "$out/listen" | tr '\n' ' ')"
else
    pass "every listener is on the loopback address"
fi

rm -rf "$out"
printf '\n%s failure(s)\n' "$failures"
exit "$failures"
