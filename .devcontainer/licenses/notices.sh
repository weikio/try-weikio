#!/bin/sh
# Writes the Try Weik.io image's /THIRD-PARTY-NOTICES.txt and /licenses/components.tsv in the form the product images
# use (README.md in this folder). The Dockerfile's notices stage runs it:
#
#   notices.sh <folder of inputs> <output folder>
#
# The inputs are each product image's notices and list form (backend, agent and apim .txt and .tsv), the module list of
# the agent's collector (otelcol-contrib.modules, from the agent image), the client's NuGet part (cli.txt and cli.tsv),
# this image's package database (dpkg/), the .NET runtime's deps.json files (runtime/), and the upstream programs this
# image adds, in bin/ with one '<program> <licence> <image reference> <path in that image>' line each in programs.txt.
# Their Go modules are downloaded into GOMODCACHE from the Go module proxy.
set -eu

in=${1:?usage: notices.sh <folder of inputs> <output folder>}
out=${2:?usage: notices.sh <folder of inputs> <output folder>}
tool=$(cd "$(dirname "$0")" && pwd)/third-party-notices.sh
: "${WEIKIO_VERSION:?WEIKIO_VERSION names the release the image is built from}"
: "${GOMODCACHE:?GOMODCACHE names the folder the Go modules are downloaded into}"
mkdir -p "$out"

# Prints the sections of a notices file whose headings the list names (keep) or does not name (drop), stopping at the
# licence texts. A rename gives a kept heading a new name, so each program's packages say whose they are.
sections() {
    awk -v mode="$1" -v names="$2" -v renames="$3" '
        BEGIN {
            n = split(names, list, "|")
            for (i = 1; i <= n; i++) named[list[i]] = 1
            n = split(renames, pairs, "|")
            for (i = 1; i <= n; i++) if (split(pairs[i], pair, "=") == 2) renamed[pair[1]] = pair[2]
        }
        { line[NR] = $0 }
        END {
            printing = 0
            for (i = 1; i <= NR; i++) {
                if (i < NR && line[i] != "" && line[i + 1] ~ /^=+$/ && length(line[i + 1]) == length(line[i])) {
                    if (line[i] == "Licence texts") break
                    printing = mode == "keep" ? (line[i] in named) : !(line[i] in named)
                    if (printing) {
                        heading = (line[i] in renamed) ? renamed[line[i]] : line[i]
                        underline = heading
                        gsub(/./, "=", underline)
                        print heading
                        print underline
                    }
                    i++
                    continue
                }
                if (printing) print line[i]
            }
        }
    ' "$4"
}

# Prints the entry of a notices file that starts with the given line, up to the blank line that ends it.
entry() {
    awk -v first="$1" '
        $0 == first { found = 1 }
        found { print; if ($0 == "") exit }
        END { if (!found) exit 1 }
    ' "$2" || { echo "notices.sh: $2 has no entry '$1'." >&2; exit 1; }
}

# The image this image's distribution packages come from, as the backend's notices name it.
base_image=$(awk 'previous == "Base image" && /^=+$/ { found = 1; next } found && NF { print; exit } { previous = $0 }' "$in/backend.txt")
[ -n "$base_image" ] || { echo "notices.sh: the backend's notices name no base image." >&2; exit 1; }

# The agent's collector as the agent's list names it, and the modules its module list names.
collector_version=$(awk -F '\t' '$1 == "artefact" && $2 == "otelcol-contrib" { print $3; exit }' "$in/agent.tsv")
[ -n "$collector_version" ] || { echo "notices.sh: the agent's list names no otelcol-contrib." >&2; exit 1; }
"$tool" go-modules "$in/otelcol-contrib.modules" > "$out/otelcol-contrib.download"

# The list form: the backend's own lines without its base image, which this image's base part lists again, then the
# packages of the agent, its Java runtime and its collector, the packages of the gateway and the client.
awk -F '\t' '$1 != "base"' "$in/backend.tsv" > "$out/components.tsv"
awk -F '\t' '$1 == "nuget" || $1 == "source" || $1 == "jdk"' "$in/agent.tsv" >> "$out/components.tsv"
awk -F '\t' '
    FILENAME == ARGV[1] { built[$0] = 1; next }
    (($1 == "artefact" && $2 == "otelcol-contrib") || ($1 == "go" && (($2 "@" $3) in built))) && !seen[$0]++
' "$out/otelcol-contrib.download" "$in/agent.tsv" >> "$out/components.tsv"
rm "$out/otelcol-contrib.download"
awk -F '\t' '$1 == "nuget" || $1 == "source"' "$in/apim.tsv" >> "$out/components.tsv"
cat "$in/cli.tsv" >> "$out/components.tsv"
NOTICES_COMPONENTS=$out/components.tsv
export NOTICES_COMPONENTS

# Each upstream program's module list, kept in the image beside the notices, and its modules in the module cache.
while read -r program licence image path; do
    [ -n "$program" ] || continue
    go version -m "$in/bin/$program" > "$out/$program.modules"
    # shellcheck disable=SC2046
    GOFLAGS=-modcacherw GOTOOLCHAIN=local GOPROXY=${GOPROXY:-https://proxy.golang.org} \
        go mod download $("$tool" go-modules "$out/$program.modules")
done < "$in/programs.txt"

{
    echo "Third-party software in the Try Weik.io image $WEIKIO_VERSION"
    echo
    sections drop "Base image" "NuGet packages=NuGet packages of the backend" "$in/backend.txt"
    sections keep "NuGet packages|Source code compiled in|Java runtime" \
        "NuGet packages=NuGet packages of the agent|Source code compiled in=Source code compiled into the agent|Java runtime=Java runtime of the agent, in /opt/weikio/agent-java" \
        "$in/agent.txt"
    echo "Collector of the agent, in /otelcol-contrib"
    echo "Collector of the agent, in /otelcol-contrib" | sed 's/./=/g'
    echo
    entry "otelcol-contrib $collector_version" "$in/agent.txt"
    sections keep "Go modules built into otelcol-contrib" "" "$in/agent.txt"
    sections keep "NuGet packages|Source code compiled in" \
        "NuGet packages=NuGet packages of the API gateway|Source code compiled in=Source code compiled into the API gateway" "$in/apim.txt"
    sections keep "NuGet packages" "NuGet packages=NuGet packages of the Weik.io CLI" "$in/cli.txt"
    echo "Upstream programs of the hub and the telemetry stores"
    echo "====================================================="
    echo
    while read -r program licence image path; do
        [ -n "$program" ] || continue
        tag=${image%@*}
        tag=${tag##*:}
        version=${tag#v}
        version=${version%%-alpine*}
        "$tool" artefact "$program" "$version" "$licence" "$image, its $path" "$(sha256sum "$in/bin/$program" | cut -d ' ' -f 1)"
    done < "$in/programs.txt"
    while read -r program licence image path; do
        [ -n "$program" ] || continue
        "$tool" go "$program" "$out/$program.modules" "$GOMODCACHE"
    done < "$in/programs.txt"
    "$tool" base "$base_image" "Ubuntu 24.04 with the .NET and ASP.NET Core runtimes, and the developer's tools this image adds" \
        "$in/dpkg" "$in/runtime"
    "$tool" texts
} > "$out/THIRD-PARTY-NOTICES.txt"
