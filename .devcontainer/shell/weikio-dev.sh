# Try Weik.io in interactive shells: completion for weikio, a notice while the platform starts, and the welcome once
# per container start.
case $- in
    *i*) ;;
    *) return 0 ;;
esac

if [ -r /usr/share/bash-completion/bash_completion ] && ! declare -F _init_completion > /dev/null 2>&1; then
    . /usr/share/bash-completion/bash_completion
fi

# Only a shell on a terminal is a person's: an editor reads the environment through an interactive shell of its own,
# which must not use up the welcome.
[ -t 1 ] || return 0

__weikio_dev_data="${WEIKIO_DEV_DATA:-/home/weikio/.weikio-dev}"
if [ -f "$__weikio_dev_data/state/ready" ]; then
    __weikio_dev_seen="${XDG_RUNTIME_DIR:-/tmp}/weikio-dev-welcome-$(id -u)"
    if [ "$(cat "$__weikio_dev_seen" 2>/dev/null)" != "$(cat "$__weikio_dev_data/run/started-at" 2>/dev/null)" ]; then
        weikio-dev welcome
        cat "$__weikio_dev_data/run/started-at" > "$__weikio_dev_seen" 2>/dev/null
    fi
    unset __weikio_dev_seen
elif [ -f "$__weikio_dev_data/state/failed" ]; then
    printf 'Weik.io did not start: %s.\nSee every process with:\n  weikio-dev status\n' "$(cat "$__weikio_dev_data/state/failed")"
else
    printf 'Weik.io is starting, at this step: %s.\nFollow it with:\n  weikio-dev wait\n' \
        "$(cat "$__weikio_dev_data/state/step" 2>/dev/null || echo "not started")"
fi
unset __weikio_dev_data
