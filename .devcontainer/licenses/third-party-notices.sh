#!/bin/sh
# Writes one part of an image's /THIRD-PARTY-NOTICES.txt to standard output, and adds the part's components to the list
# form of the notices, the file NOTICES_COMPONENTS names. The list has one line per component with five fields
# separated by tabs: the part, the component's name, its version, its licence as an SPDX expression, and where that
# licence's text is: 'entry' when the component's own licence files are copied in full under its entry, 'end' when it is
# the standard text at the end of the notices, or a path in the image. The Dockerfiles run the script inside their build
# stages, where only sh, sed, awk, grep, find and sort are sure to exist. The npm part runs in the Node stage and uses
# node, and the launcher part needs unzip.
#
#   third-party-notices.sh nuget <deps.json or project.assets.json> [<packages folder>]
#   third-party-notices.sh npm <node_modules/.package-lock.json>
#   third-party-notices.sh jdk <the release file of the JDK the runtime is linked from> <where its legal notices are>
#   third-party-notices.sh artefact <name> <version> <licence> <download URL> <sha256> [<where its licence text is>]
#   third-party-notices.sh source <name> <version> <licence> <project URL> <folder its files were copied to> <what they are built into>
#   third-party-notices.sh launcher <jar> <download URL> <sha256> <where the image keeps it>
#   third-party-notices.sh go-modules <module list 'go version -m' wrote>
#   third-party-notices.sh go <program> <module list 'go version -m' wrote> <module cache>
#   third-party-notices.sh base <image reference> <what it holds> <dpkg folder> [<folder of the .NET runtime's deps.json files>]
#   third-party-notices.sh texts
#
# go-modules prints the module@version of every module a Go program is built from, for 'go mod download'. texts reads
# the list form and writes the standard text of every licence it names. A component whose own files name no licence,
# name one the script does not recognise, or name several to choose from takes the licence its line in
# licence-reviews.txt gives by part, name and version. The standard texts are texts/<SPDX id>.txt.
# Both are read from the folder the script is in, or from the folder NOTICES_ROOT names, which holds the same paths.
set -eu

root=${NOTICES_ROOT:-$(cd "$(dirname "$0")" && pwd)}
texts=$root/texts
reviews=$root/licence-reviews.txt

# A licence or notice file's name, matched in lower case, and the endings of the files that only look like one.
licence_file_names='(^|[._-])(licen[cs]es?|copying|notices?|unlicense|copyright|patents)([._-][^/]*)?$'
not_licence_files='[.](class|java|kt|groovy|go|s|c|h|js|mjs|cjs|ts|py|sh|properties|xml|json|ya?ml|proto|tmpl|png|gif|jpe?g|svg|ico|jar|so|dll|dylib)$'
# Licences whose text asks for a statement of where the source code of the covered work is.
copyleft='(^|[^A-Za-z])(EPL|MPL|CPL|CDDL|LGPL|GPL)-'

usage() {
    echo "Usage: $0 nuget <deps.json or project.assets.json> [<packages folder>] | npm <lock file> | jdk <release file> <legal directory> | artefact <name> <version> <licence> <url> <sha256> [<licence file>] | source <name> <version> <licence> <url> <folder> <built into> | launcher <jar> <url> <sha256> <path in the image> | go-modules <module list> | go <program> <module list> <module cache> | base <image> <description> <dpkg folder> [<runtime deps.json folder>] | texts" >&2
    exit 2
}

fail() {
    echo "$*" >&2
    exit 1
}

# Adds one component to the list form.
component() {
    [ -n "${NOTICES_COMPONENTS:-}" ] || fail "NOTICES_COMPONENTS is not set. Set it to the file the parts add their components to, the list that is copied to /licenses/components.tsv."
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$NOTICES_COMPONENTS"
}

# Copies a licence or notice file in full under an entry, indented so the entry's own lines stay apart from it.
in_full() {
    echo "  $2, in full:"
    echo
    awk '{ sub(/\r$/, ""); if ($0 == "") print ""; else print "    " $0 }' "$1"
    echo
}

# The files of a folder that hold a licence or a notice, as paths relative to it, in a stable order. With a depth, only
# the files that many levels down or less.
licence_files() {
    if [ $# -ge 2 ]; then
        (cd "$1" && find . -maxdepth "$2" -type f)
    else
        (cd "$1" && find . -type f)
    fi | sed 's|^\./||' | awk -v names="$licence_file_names" -v code="$not_licence_files" '
        { base = $0; sub(/.*\//, "", base); low = tolower(base) }
        low ~ names && low !~ code && $0 !~ /(^|\/)testdata\// { print }
    ' | LC_ALL=C sort
}

# The licence files among licence_files that say under what terms the component itself is given, without its notices
# and the lists of what others' software it includes.
licence_texts_only() {
    awk '{ base = $0; sub(/.*\//, "", base); low = tolower(base) } low !~ /notice|notes|third/ && low !~ /^(copyright|patents)/ { print }'
}

# Prints '<file><tab><SPDX id>' for every file named on standard input, the id empty when the file is not the standard
# text of exactly one licence in licenses/texts. Both texts are compared as their words in lower case, without copyright
# lines, addresses and what follows 'END OF TERMS AND CONDITIONS': the file is that licence when at least 95 % of the
# standard text's words are in it, at least 95 % of its words are in the standard text, and no other licence comes
# within 2 % of that.
identify() {
    [ -d "$texts" ] || fail "The standard licence texts '$texts' do not exist."
    set -- "$texts"/*.txt
    awk -v threshold=0.95 -v margin=0.02 '
        function words(file, bag,    line, low, stop, at, n, i, parts, total) {
            split("", bag)
            total = 0
            stop = 0
            while (!stop && (getline line < file) > 0) {
                sub(/\r$/, "", line)
                low = tolower(line)
                sub(/^[ \t#*\/;!-]+/, "", low)
                if (low ~ /^(copyright|\(c\)|©)/ && low !~ /^copyright[ \t]+(notice|holder|owner|and|law|license|licence|statement|protection)/) continue
                if (low ~ /^all rights reserved\.?[ \t]*$/) continue
                low = tolower(line)
                at = index(low, "end of terms and conditions")
                if (at > 0) {
                    low = substr(low, 1, at - 1)
                    stop = 1
                }
                gsub(/https?:\/\/[^ \t]+/, " ", low)
                gsub(/licence/, "license", low)
                gsub(/&/, " and ", low)
                gsub(/[^a-z0-9]+/, " ", low)
                n = split(low, parts, " ")
                for (i = 1; i <= n; i++) {
                    bag[parts[i]]++
                    total++
                }
            }
            close(file)
            return total
        }
        BEGIN {
            for (a = 1; a < ARGC; a++) {
                file = ARGV[a]
                ARGV[a] = ""
                id = file
                sub(/.*\//, "", id)
                sub(/\.txt$/, "", id)
                if (id ~ /exception/) continue
                size[id] = words(file, one)
                ids[++count] = id
                for (w in one) standard[id, w] = one[w]
            }
        }
        {
            total = words($0, candidate)
            best = ""
            top = 0
            second = 0
            for (k = 1; total > 0 && k <= count; k++) {
                id = ids[k]
                shared = 0
                for (w in candidate) if ((id, w) in standard) shared += candidate[w] < standard[id, w] ? candidate[w] : standard[id, w]
                score = shared / size[id]
                if (shared / total < score) score = shared / total
                if (score > top) {
                    second = top
                    top = score
                    best = id
                } else if (score > second) {
                    second = score
                }
            }
            if (top < threshold || top - second < margin) best = ""
            print $0 "\t" best
        }
    ' "$@"
}

# Reads licence names and addresses as a pom, a manifest or a package names them, one per line, and prints the SPDX id
# of each, or '?' for one the script does not recognise.
recognise() {
    awk -v texts="$texts" '
        function known(id) { return (getline line < (texts "/" id ".txt")) > 0 ? close(texts "/" id ".txt") + 1 : 0 }
        {
            name = $0
            gsub(/^[ \t"]+|[ \t"]+$/, "", name)
            low = tolower(name)
            gsub(/[()]/, "", low)
            if (name ~ /^[A-Za-z0-9.+-]+$/ && known(name)) id = name
            else if (low ~ /apache\.org\/licenses\/license-2\.0/ || low ~ /^(the )?apache( software)?( license)?,? *(version |v)?2(\.0)?$/ || low ~ /^apache license,? version 2\.0$/) id = "Apache-2.0"
            else if (low ~ /mit-license|opensource\.org\/licenses?\/mit($|[^a-z0-9])/ || low ~ /^(the )?mit( license)?$/) id = "MIT"
            else if (low ~ /epl-v20|epl-2\.0/ || low ~ /^eclipse public license[ ,-]*v?(ersion)? *2\.0$/ || low == "epl 2.0") id = "EPL-2.0"
            else if (low ~ /epl-v10|epl-1\.0/ || low ~ /^eclipse public license[ ,-]*v?(ersion)? *1\.0$/ || low == "epl 1.0") id = "EPL-1.0"
            else if (low ~ /edl-v10/ || low ~ /^eclipse distribution license[ ,-]*v?(ersion)? *1\.0$/ || low == "edl 1.0") id = "BSD-3-Clause"
            else if (low ~ /opensource\.org\/licenses\/bsd-3-clause/ || low ~ /^(the )?(new|revised) bsd license$/ || low ~ /^(the )?bsd 3-clause license$/) id = "BSD-3-Clause"
            else if (low ~ /opensource\.org\/licenses\/bsd-2-clause/ || low ~ /^(the )?simplified bsd license$/ || low ~ /^(the )?bsd 2-clause license$/) id = "BSD-2-Clause"
            else if (low ~ /classpath\/license/ || low ~ /^gpl2 w\/ cpe$/) id = "GPL-2.0-only WITH Classpath-exception-2.0"
            else if (low ~ /mozilla\.org\/mpl\/2\.0/ || low ~ /^mozilla public license,? (version |v)?2\.0$/) id = "MPL-2.0"
            else if (low ~ /opensource\.org\/licenses\/cpl1\.0/ || low ~ /^common public license( - v| version |, version )?1\.0$/) id = "CPL-1.0"
            else id = "?"
            print id
        }
    '
}

# The reviewed line of one component: its licence and its source address, each '-' where the line leaves it to the
# component's own files, and what the review read, separated by tabs. Nothing when the reviews have no line for it.
review() {
    [ -f "$reviews" ] || return 0
    awk -F '\t' -v part="$1" -v name="$2" -v version="$3" '
        /^#/ || NF == 0 { next }
        $1 == part && $2 == name && $3 == version { print $4 "\t" $5 "\t" $6; exit }
    ' "$reviews"
}

# The line of an entry that names where its licence comes from: the component's own files, or its reviewed line.
licence_source() {
    local part=$1 name=$2 version=$3 licence=$4 own=$5 whence=$6
    if [ "$licence" = "$(printf '%s\n' "$own" | grep -v '^$' | LC_ALL=C sort -u)" ]; then
        echo "  Licence named by: $whence"
    else
        echo "  Licence reviewed: $(review "$part" "$name" "$version" | cut -f 3)"
    fi
}

# Decides a component's licence from what its own files name and its reviewed line, and prints it. $4 holds the SPDX ids
# its own files name, one per line, '?' for a name not recognised, and $5 says where they were read, for the refusal.
decide() {
    local part=$1 name=$2 version=$3 own=$4 place=$5 reviewed distinct
    reviewed=$(review "$part" "$name" "$version" | cut -f 1)
    distinct=$(printf '%s\n' "$own" | grep -v '^$' | LC_ALL=C sort -u | awk '{ printf "%s%s", (NR > 1 ? " and " : ""), $0 }')
    case $distinct in
        ""|*"?"*|*" and "*)
            [ -n "$reviewed" ] && [ "$reviewed" != "-" ] || fail "$part component $name $version names $(if [ -z "$distinct" ]; then echo "no licence"; elif [ "$distinct" = "?" ]; then echo "a licence this script does not recognise"; else echo "the licences $distinct"; fi) in $place. Read its licence, and give it the line '$part<tab>$name<tab>$version<tab><SPDX expression><tab>-<tab><what you read>' in licence-reviews.txt."
            echo "$reviewed" ;;
        *)
            [ -z "$reviewed" ] || [ "$reviewed" = "-" ] || fail "licence-reviews.txt gives $part component $name $version the licence $reviewed, while its own files name $distinct. Write '-' in place of the licence on its line."
            echo "$distinct" ;;
    esac
}

nuspec_value() {
    printf '%s\n' "$1" | sed -n "s|.*<$2[^>]*>\\([^<]*\\)</$2>.*|\\1|p" |
        sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&apos;/'"'"'/g; s/&#169;/(c)/g; s/&#xA9;/(c)/g; s/©/(c)/g; s/&amp;/\&/g'
}

nuget() {
    local graph=$1 packages=${2:-${NUGET_PACKAGES:-$HOME/.nuget/packages}}
    [ -f "$graph" ] || fail "The dependency file '$graph' does not exist. Run 'dotnet publish' before writing the notices."

    echo "NuGet packages"
    echo "=============="
    echo

    # Both files list one "<id>/<version>": { key per line under "libraries", each with a "type" line inside it.
    awk '
        /^  "libraries": \{/ { inside = 1; next }
        inside && /^  \}/ { inside = 0 }
        inside && /^    "[^"]+\/[^"]+": \{/ { key = $1; gsub(/^"|":$/, "", key) }
        inside && /"type": "package"/ { print key }
    ' "$graph" | LC_ALL=C sort -t / -k 1,1f -k 2,2 | while IFS=/ read -r id version; do
        folder=$packages/$(echo "$id" | awk '{ print tolower($0) }')/$(echo "$version" | awk '{ print tolower($0) }')
        nuspec=$folder/$(echo "$id" | awk '{ print tolower($0) }').nuspec
        [ -f "$nuspec" ] || fail "The package '$id' $version is in '$graph' but its nuspec '$nuspec' is missing. Restore the project before writing the notices."

        joined=$(awk '{ printf "%s ", $0 }' "$nuspec")
        own=""
        expression=$(printf '%s\n' "$joined" | sed -n 's|.*<license type="expression">\([^<]*\)</license>.*|\1|p')
        file=$(printf '%s\n' "$joined" | sed -n 's|.*<license type="file">\([^<]*\)</license>.*|\1|p')
        url=$(nuspec_value "$joined" licenseUrl)
        copyright=$(nuspec_value "$joined" copyright)
        project=$(nuspec_value "$joined" projectUrl)

        if [ -n "$expression" ]; then
            licence=$expression
            where=end
        elif [ -n "$file" ]; then
            [ -f "$folder/$file" ] || fail "The package '$id' $version names its licence file '$file', which '$folder' lacks. Restore the package again before writing the notices."
            own=$(printf '%s\n' "$folder/$file" | identify | cut -f 2)
            licence=$(decide nuget "$id" "$version" "${own:-?}" "its licence file $file")
            where=entry
        elif [ -n "$url" ]; then
            own=$(printf '%s\n' "$url" | recognise)
            licence=$(decide nuget "$id" "$version" "$own" "its licence address $url")
            where=end
        else
            fail "The package '$id' $version names no licence in '$nuspec'. Review it before it ships in an image."
        fi

        echo "$id $version"
        if [ "$where" = entry ]; then
            echo "  Licence: $licence, the package's $file below"
        else
            echo "  Licence: $licence, whose text is at the end of this file"
        fi
        [ -n "$expression" ] || licence_source nuget "$id" "$version" "$licence" "$own" "${file:-its licence address}"
        [ -z "$copyright" ] || echo "  Copyright: $copyright"
        [ -z "$project" ] || echo "  Project: $project"
        [ "$where" != entry ] || in_full "$folder/$file" "$file"
        echo
        component nuget "$id" "$version" "$licence" "$where"
    done
}

npm_packages() {
    local lock=$1
    [ -f "$lock" ] || fail "The lock file '$lock' does not exist. Run 'npm ci' before writing the notices."
    [ -n "${NOTICES_COMPONENTS:-}" ] || fail "NOTICES_COMPONENTS is not set. Set it to the file the parts add their components to, the list that is copied to /licenses/components.tsv."

    echo "npm packages of the admin UI"
    echo "============================"
    echo

    # Only what the UI's production build bundles: a package marked dev or devOptional is a build tool or a type. A
    # package whose package.json names no licence takes the licence its reviewed line gives for that exact version.
    node -e '
        const fs = require("fs");
        const path = require("path");
        const [lock, reviews, list, names, code] = process.argv.slice(1);
        const root = path.dirname(path.dirname(lock));
        const packages = JSON.parse(fs.readFileSync(lock, "utf8")).packages;
        const reviewed = new Map();
        if (fs.existsSync(reviews)) {
            for (const line of fs.readFileSync(reviews, "utf8").split("\n")) {
                const fields = line.split("\t");
                if (line.startsWith("#") || fields.length < 5 || fields[0] !== "npm") continue;
                reviewed.set(`${fields[1]}@${fields[2]}`, { licence: fields[3], read: fields[5] ?? "" });
            }
        }
        const isLicenceFile = new RegExp(names);
        const isCode = new RegExp(code);
        const rows = [];
        for (const [key, entry] of Object.entries(packages)) {
            if (!key.startsWith("node_modules/") || entry.dev || entry.devOptional) continue;
            const name = key.slice(key.lastIndexOf("node_modules/") + "node_modules/".length);
            const folder = path.join(root, key);
            let manifest = {};
            try { manifest = JSON.parse(fs.readFileSync(path.join(folder, "package.json"), "utf8")); } catch { }
            const own = entry.license || (typeof manifest.license === "object" ? manifest.license?.type : manifest.license);
            const review = reviewed.get(`${name}@${entry.version}`);
            if (own && review && review.licence !== "-") {
                console.error(`licence-reviews.txt gives npm component ${name} ${entry.version} the licence ${review.licence}, while its package.json names ${own}. Write '\''-'\'' in place of the licence on its line.`);
                process.exit(1);
            }
            const licence = own || (review && review.licence !== "-" ? review.licence : undefined);
            if (!licence) {
                console.error(`npm component ${name} ${entry.version} names no licence in its package.json. Read its licence, and give it the line '\''npm<tab>${name}<tab>${entry.version}<tab><SPDX expression><tab>-<tab><what you read>'\'' in licence-reviews.txt.`);
                process.exit(1);
            }
            let files = [];
            try {
                files = fs.readdirSync(folder)
                    .filter(file => isLicenceFile.test(file.toLowerCase()) && !isCode.test(file.toLowerCase()) && fs.statSync(path.join(folder, file)).isFile())
                    .sort();
            } catch { }
            const author = typeof manifest.author === "string" ? manifest.author : manifest.author?.name;
            const project = manifest.homepage || (typeof manifest.repository === "string" ? manifest.repository : manifest.repository?.url);
            rows.push({ name, version: entry.version, licence, reviewed: own ? undefined : review.read, author, project, folder, files });
        }
        rows.sort((a, b) => a.name.localeCompare(b.name, "en"));
        const out = [];
        for (const row of rows) {
            out.push(`${row.name} ${row.version}`);
            out.push(row.files.length > 0 ? `  Licence: ${row.licence}, the package\u0027s own files are below` : `  Licence: ${row.licence}, whose text is at the end of this file`);
            if (row.reviewed !== undefined) out.push(`  Licence reviewed: ${row.reviewed}`);
            if (row.author) out.push(`  Author: ${row.author}`);
            if (row.project) out.push(`  Project: ${row.project}`);
            for (const file of row.files) {
                out.push(`  ${file}, in full:`, "");
                for (const line of fs.readFileSync(path.join(row.folder, file), "utf8").replace(/\r?\n$/, "").split(/\r?\n/)) out.push(line === "" ? "" : `    ${line}`);
                out.push("");
            }
            out.push("");
            fs.appendFileSync(list, ["npm", row.name, row.version, row.licence, row.files.length > 0 ? "entry" : "end"].join("\t") + "\n");
        }
        process.stdout.write(out.join("\n") + "\n");
    ' "$lock" "$reviews" "$NOTICES_COMPONENTS" "$licence_file_names" "$not_licence_files"
}

jdk() {
    local release=$1 legal=$2 implementor build version repository commit
    [ -f "$release" ] || fail "The Java runtime's release file '$release' does not exist."
    field() { sed -n "s/^$1=\"\\(.*\\)\"$/\\1/p" "$release"; }
    implementor=$(field IMPLEMENTOR)
    build=$(field IMPLEMENTOR_VERSION)
    version=$(field JAVA_RUNTIME_VERSION)
    repository=$(field SOURCE_REPO)
    commit=$(field SOURCE | sed -n 's/.*git:\([0-9a-f]*\)$/\1/p')
    [ -n "$version" ] || fail "The Java runtime's release file '$release' names no JAVA_RUNTIME_VERSION. Pass the release file of the JDK the runtime was linked from."

    echo "Java runtime"
    echo "============"
    echo
    echo "OpenJDK $version"
    echo "  $implementor $build, reduced with jlink to the modules this image needs"
    echo "  Licence: GPL-2.0-only WITH Classpath-exception-2.0, whose texts are at the end of this file"
    echo "  Notices: $legal, one directory per module"
    echo "  Source: ${repository:-https://github.com/adoptium/jdk21u}${commit:+, commit $commit}, and the source offer in /NOTICE"
    echo
    component jdk OpenJDK "$version" "GPL-2.0-only WITH Classpath-exception-2.0" "$legal"
}

artefact() {
    [ $# -ge 5 ] || usage
    echo "$1 $2"
    echo "  Licence: $3"
    echo "  Downloaded from: $4"
    echo "  sha256: $5"
    [ $# -lt 6 ] || echo "  Licence text: $6"
    echo
    component artefact "$1" "$2" "$3" "${6:-end}"
}

# Source files of others copied into the repository and compiled into the program. The copyright is read from the
# files' own headers, so the notice names what the copied files say.
compiled_source() {
    [ $# -eq 6 ] || usage
    local folder=$5 copyright
    [ -d "$folder" ] || fail "The folder '$folder' that $1 was copied to does not exist. Copy its files back, or remove $1 from the notices."
    copyright=$(grep -rh -m 1 '^// Copyright' "$folder" | sed 's|^// ||' | sort -u | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 }')
    # Source files that carry no header of their own take the copyright line of the folder's NOTICE.
    [ -n "$copyright" ] || [ ! -f "$folder/NOTICE" ] || copyright=$(grep -m 1 '^Copyright' "$folder/NOTICE" || true)
    [ -n "$copyright" ] || fail "No file under '$folder' has a '// Copyright' header, and the folder has no NOTICE with a Copyright line. Copy $1's files with their licence headers."
    echo "$1 $2"
    echo "  Licence: $3, whose text is at the end of this file"
    echo "  Copyright: $copyright"
    echo "  Project: $4"
    echo "  Built into: $6"
    echo
    component source "$1" "$2" "$3" end
}

# Extracts the entries of an archive that match the patterns into a folder. A pattern that matches nothing is no error:
# busybox's unzip says nothing then, and Info-ZIP's exits 11.
unpack() {
    local archive=$1 into=$2 status=0
    shift 2
    mkdir -p "$into"
    unzip -q -o "$archive" "$@" -d "$into" 2> "$into.err" || status=$?
    [ "$status" -eq 0 ] || [ "$status" -eq 11 ] || fail "unzip could not read '$archive': $(cat "$into.err")"
    rm -f "$into.err"
}

# The patterns that extract a jar's licence and notice files, its manifest and its embedded pom.
jar_patterns() {
    for name in 'LICEN[CS]E' 'licen[cs]e' 'Licen[cs]e' 'NOTICE' 'notice' 'Notice' 'COPYING' 'copying' 'Copying' 'UNLICENSE' 'COPYRIGHT' 'copyright'; do
        printf '%s*\nMETA-INF/%s*\n' "$name" "$name"
    done
    echo 'META-INF/MANIFEST.MF'
    echo 'META-INF/maven/*'
}

# The licences a pom's licenses element lists, one per line as '<name><tab><address>'.
pom_licences() {
    awk '
        function between(s, open, shut,    a, b) {
            a = index(s, open)
            if (a == 0) return ""
            s = substr(s, a + length(open))
            b = index(s, shut)
            s = b > 0 ? substr(s, 1, b - 1) : ""
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            return s
        }
        { text = text " " $0 }
        END {
            start = index(text, "<licenses>")
            stop = index(text, "</licenses>")
            if (start == 0 || stop <= start) exit
            block = substr(text, start, stop - start)
            while ((at = index(block, "<license>")) > 0) {
                block = substr(block, at + 9)
                shut = index(block, "</license>")
                one = shut > 0 ? substr(block, 1, shut - 1) : block
                print between(one, "<name>", "</name>") "\t" between(one, "<url>", "</url>")
                block = shut > 0 ? substr(block, shut) : ""
            }
        }
    ' "$1"
}

# The SPDX ids the licences of a pom name, one per line. A licence whose name is not recognised is recognised by its
# address.
pom_ids() {
    pom_licences "$1" | while IFS="$(printf '\t')" read -r name url; do
        id=$(printf '%s\n' "$name" | recognise)
        [ "$id" != "?" ] || [ -z "$url" ] || id=$(printf '%s\n' "$url" | recognise)
        echo "$id"
    done
}

# The SPDX ids a jar manifest's Bundle-License names, one per line. Its clauses are separated by commas that open a
# quoted name or an address, so a name with a comma in it stays one clause.
manifest_ids() {
    awk '
        /^ / { if (inside) value = value substr($0, 2); next }
        { sub(/\r$/, "") }
        inside { inside = 0 }
        /^Bundle-License:/ { inside = 1; value = substr($0, 17) }
        END {
            gsub(/\r/, "", value)
            gsub(/,[ ]*"/, "\n\"", value)
            gsub(/,[ ]*http/, "\nhttp", value)
            n = split(value, clauses, "\n")
            for (i = 1; i <= n; i++) {
                clause = clauses[i]
                link = ""
                if (match(clause, /;[ ]*link="?[^";]+/)) {
                    link = substr(clause, RSTART, RLENGTH)
                    sub(/^;[ ]*link="?/, "", link)
                }
                sub(/;.*/, "", clause)
                gsub(/^[ "]+|[ "]+$/, "", clause)
                if (clause != "") print clause "\t" link
            }
        }
    ' "$1" | while IFS="$(printf '\t')" read -r name link; do
        id=$(printf '%s\n' "$name" | recognise)
        [ "$id" != "?" ] || [ -z "$link" ] || id=$(printf '%s\n' "$link" | recognise)
        echo "$id"
    done
}

# The licence files of a jar that say under what terms the jar itself is given: those at its root and in its META-INF,
# without the licences of the software of others it includes, which a folder of their own holds.
jar_licence_texts() {
    licence_files "$1" 2 | licence_texts_only | grep -E '^(META-INF/)?[^/]+$' || true
}

# One property of a pom.properties file.
property() {
    sed -n "s/^$2=//p" "$1" | tr -d '\r' | head -n 1
}

# Writes the entry of one jar whose licence and notice files, manifest and embedded pom were extracted into a folder,
# and adds it to the list form. The licence is the one its pom names, else its manifest, else its own licence files.
# Its name and version are those its file name is made of, as '<name>-<version>.jar'.
jar_entry() {
    local folder=$1 file=$2 identified=$3 extra=$4 name="" version="" group="" release="" properties="" candidate pom=""
    local own="" whence="" licence reviewed_source source where files
    for candidate in $(find "$folder/META-INF/maven" -name pom.properties 2>/dev/null | LC_ALL=C sort); do
        case $file in
            "$(property "$candidate" artifactId)-"*) if [ -z "$properties" ]; then properties=$candidate; else properties=ambiguous; fi ;;
        esac
    done
    if [ -n "$properties" ] && [ "$properties" != ambiguous ]; then
        name=$(property "$properties" artifactId)
        group=$(property "$properties" groupId)
        release=$(property "$properties" version)
        pom=$(dirname "$properties")/pom.xml
    else
        name=$(printf '%s\n' "${file%.jar}" | sed -n 's/-[0-9].*//p')
    fi
    version=${file%.jar}
    version=${version#"$name"-}
    [ -n "$name" ] && [ "$version" != "${file%.jar}" ] || fail "The jar '$file' names its artifact in no pom.properties and its version nowhere in its file name, so its entry cannot name it."

    if [ -f "$pom" ]; then
        own=$(pom_ids "$pom")
        whence="its pom"
    fi
    case $own in
        ""|*"?"*)
            if [ -f "$folder/META-INF/MANIFEST.MF" ] && [ -n "$(manifest_ids "$folder/META-INF/MANIFEST.MF")" ]; then
                own=$(manifest_ids "$folder/META-INF/MANIFEST.MF")
                whence="its manifest"
            fi ;;
    esac
    case $own in
        ""|*"?"*)
            files=$(jar_licence_texts "$folder")
            if [ -n "$files" ]; then
                own=$(printf '%s\n' "$files" | while read -r f; do
                    id=$(awk -F '\t' -v f="$folder/$f" '$1 == f { print $2; exit }' "$identified")
                    echo "${id:-?}"
                done)
                whence="its licence files"
            fi ;;
    esac
    # A jar the part cannot decide is written to the refusals, and the part fails once it has read every jar.
    licence=$(decide launcher "$name" "$version" "$own" "${whence:-its pom, its manifest or its licence files}") || {
        echo "$file" >> "$work/refused"
        return 0
    }
    files=$(licence_files "$folder")
    where=end
    [ -z "$files" ] || where=entry
    echo "$name $version"
    echo "  Licence: $licence$(if [ "$where" = entry ]; then echo ", its own files are below"; else echo ", whose text is at the end of this file"; fi)"
    licence_source launcher "$name" "$version" "$licence" "$own" "$whence"
    [ -z "$group" ] || echo "  Maven: $group:$name:$release"
    if printf '%s\n' "$licence" | grep -Eq "$copyleft"; then
        reviewed_source=$(review launcher "$name" "$version" | cut -f 2)
        if [ -n "$reviewed_source" ] && [ "$reviewed_source" != "-" ]; then
            source=$reviewed_source
        elif [ -n "$group" ]; then
            source=https://repo1.maven.org/maven2/$(echo "$group" | tr . /)/$name/$release/$name-$release-sources.jar
        else
            echo "The jar '$file' is under $licence, which asks where its source code is, and names no Maven group to find it by. Give its source address in its line in licence-reviews.txt." >&2
            echo "$file" >> "$work/refused"
            return 0
        fi
        echo "  Source: $source, the source code of this version"
    fi
    [ -z "$extra" ] || printf '%s\n' "$extra"
    printf '%s\n' "$files" | while read -r f; do
        [ -z "$f" ] || in_full "$folder/$f" "$f"
    done
    echo
    component launcher "$name" "$version" "$licence" "$where"
}

launcher() {
    [ $# -eq 4 ] || usage
    local jar=$1 url=$2 sha256=$3 location=$4 file lib folder
    [ -f "$jar" ] || fail "The launcher '$jar' does not exist."
    command -v unzip > /dev/null 2>&1 || fail "The launcher part reads jars with unzip, which this stage lacks. Run it in a stage that has unzip."
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    file=$(basename "$jar")

    # The patterns go to unzip as they are: with file name expansion off, a file of the folder the part runs in that
    # matches one does not replace it.
    set -f
    # shellcheck disable=SC2046
    unpack "$jar" "$work/outer" 'BOOT-INF/lib/*.jar' $(jar_patterns)
    [ -d "$work/outer/BOOT-INF/lib" ] || fail "The launcher '$jar' holds no jar under BOOT-INF/lib. Pass the Camel launcher jar itself."
    for lib in $(cd "$work/outer/BOOT-INF/lib" && ls | LC_ALL=C sort); do
        # shellcheck disable=SC2046
        unpack "$work/outer/BOOT-INF/lib/$lib" "$work/lib/$lib" $(jar_patterns)
    done
    set +f
    rm -rf "$work/outer/BOOT-INF"

    # Every licence file is compared with the standard texts in one pass.
    for folder in "$work/outer" "$work"/lib/*; do
        jar_licence_texts "$folder" | sed "s|^|$folder/|"
    done | identify > "$work/identified"

    echo "Camel launcher $file"
    echo "Camel launcher $file" | sed 's/./=/g'
    echo
    jar_entry "$work/outer" "$file" "$work/identified" "$(printf '  Downloaded from: %s\n  sha256: %s\n  In this image: %s' "$url" "$sha256" "$location")"
    echo "The libraries inside $file, in its BOOT-INF/lib"
    echo "The libraries inside $file, in its BOOT-INF/lib" | sed 's/./-/g'
    echo
    for lib in $(cd "$work/lib" && ls | LC_ALL=C sort); do
        jar_entry "$work/lib/$lib" "$lib" "$work/identified" ""
    done
    [ ! -s "$work/refused" ] || exit 1
}

# The modules a Go program is built from, as 'go version -m' lists them, one per line as
# '<path><tab><version><tab><folder><tab><checksum>', each module replaced by another module as its replacement. A module
# replaced by a folder of the program's own source has no version of its own, so it is the module it replaces, with that
# folder in the third field. The field is '-' for every other module, because a shell's read joins the tabs around an
# empty field.
go_module_lines() {
    [ -f "$1" ] || fail "The module list '$1' does not exist. Write it with 'go version -m <program> > $1'."
    awk -F '\t' '
        $2 == "dep" { n++; path[n] = $3; version[n] = $4; sum[n] = $5 }
        $2 == "=>" && $4 ~ /^v/ { path[n] = $3; version[n] = $4; sum[n] = $5; next }
        $2 == "=>" { folder[n] = $3 }
        END { for (i = 1; i <= n; i++) print path[i] "\t" version[i] "\t" (folder[i] == "" ? "-" : folder[i]) "\t" sum[i] }
    ' "$1"
}

go_modules() {
    go_module_lines "$1" | while IFS="$(printf '\t')" read -r path version folder sum; do
        [ -n "$version" ] || fail "The module $path of '$1' is replaced by a folder, so no version of it can be downloaded. Build the program from published modules."
        echo "$path@$version"
    done
}

# A module path or version as the module cache spells it: each capital letter as '!' and the letter in lower case.
escaped() {
    printf '%s\n' "$1" | sed 's/[A-Z]/!&/g' | tr 'A-Z' 'a-z'
}

go_part() {
    [ $# -eq 3 ] || usage
    local program=$1 list=$2 cache=$3 path version sum folder dir hash own licence files where
    [ -d "$cache" ] || fail "The module cache '$cache' does not exist. Download the modules with 'go mod download' into it first."
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    go_module_lines "$list" > "$work/modules"
    [ -s "$work/modules" ] || fail "The module list '$list' names no module. Write it with 'go version -m <program>' on a program built with modules."

    while IFS="$(printf '\t')" read -r path version folder sum; do
        dir=$cache/$(escaped "$path")@$(escaped "$version")
        [ -d "$dir" ] || fail "The module $path $version that $program is built from is not in '$cache'. Download it with 'go mod download $path@$version'."
        hash=$cache/cache/download/$(escaped "$path")/@v/$(escaped "$version").ziphash
        if [ -n "$sum" ]; then
            [ -f "$hash" ] && [ "$(cat "$hash")" = "$sum" ] || fail "The module $path $version in '$cache' does not have the checksum $sum that $program records for it. Download it again with 'go mod download $path@$version'."
        fi
        licence_files "$dir" 1 | licence_texts_only | sed "s|^|$dir/|" >> "$work/candidates"
    done < "$work/modules"
    touch "$work/candidates"
    identify < "$work/candidates" > "$work/identified"

    echo "Go modules built into $program"
    echo "Go modules built into $program" | sed 's/./=/g'
    echo
    while IFS="$(printf '\t')" read -r path version folder sum; do
        dir=$cache/$(escaped "$path")@$(escaped "$version")
        own=$(licence_files "$dir" 1 | licence_texts_only | while read -r f; do
            id=$(awk -F '\t' -v f="$dir/$f" '$1 == f { print $2; exit }' "$work/identified")
            echo "${id:-?}"
        done)
        licence=$(decide go "$path" "$version" "$own" "its licence files") || {
            echo "$path" >> "$work/refused"
            continue
        }
        files=$(licence_files "$dir")
        where=end
        [ -z "$files" ] || where=entry
        echo "$path $version"
        echo "  Licence: $licence$(if [ "$where" = entry ]; then echo ", its own files are below"; else echo ", whose text is at the end of this file"; fi)"
        licence_source go "$path" "$version" "$licence" "$own" "its licence files"
        echo "  Source: https://proxy.golang.org/$(escaped "$path")/@v/$(escaped "$version").zip${sum:+, checksum $sum}"
        [ "$folder" = - ] || echo "  Built from: the folder $folder of the program's own source, in place of this version"
        printf '%s\n' "$files" | while read -r f; do
            [ -z "$f" ] || in_full "$dir/$f" "$f"
        done
        echo
        component go "$path" "$version" "$licence" "$where"
    done < "$work/modules"
    [ ! -s "$work/refused" ] || exit 1
}

base() {
    [ $# -eq 3 ] || [ $# -eq 4 ] || usage
    local image=$1 description=$2 dpkg=$3 runtime=${4:-} status
    [ -d "$dpkg" ] || fail "The package database '$dpkg' does not exist. Copy /var/lib/dpkg from the runtime image first."
    echo "Base image"
    echo "=========="
    echo
    echo "$image"
    echo "  $description"
    echo "  The source offer for the packages licensed under the GPL is in /NOTICE."
    echo

    if [ -n "$runtime" ]; then
        for deps in $(find "$runtime" -name '*.deps.json' | LC_ALL=C sort); do
            awk '
                /^  "libraries": \{/ { inside = 1; next }
                inside && /^  \}/ { inside = 0 }
                inside && /^    "[^"]+\/[^"]+": \{/ { key = $1; gsub(/^"|":$/, "", key) }
                inside && /"type": "package"/ { print key }
            ' "$deps"
        done | LC_ALL=C sort -u | while IFS=/ read -r id version; do
            echo "$id $version"
            echo "  Licence: MIT, in /usr/share/dotnet/LICENSE.txt, and the notices of the software the runtime contains are in"
            echo "  /usr/share/dotnet/ThirdPartyNotices.txt"
            echo
            component base "$id" "$version" MIT /usr/share/dotnet/LICENSE.txt
        done
    fi

    echo "The distribution packages, each with its licence in the copyright file named under it:"
    echo
    # The full image keeps every package in one status file, a chiseled one may keep one file per package.
    status=$(find "$dpkg" -maxdepth 2 \( -path "$dpkg/status" -o -path "$dpkg/status.d/*" \) -type f ! -name '*.md5sums' | LC_ALL=C sort)
    [ -n "$status" ] || fail "'$dpkg' holds neither a status file nor a status.d folder. Copy /var/lib/dpkg from the runtime image."
    # shellcheck disable=SC2086
    awk '
        function emit() {
            if (package != "" && (state == "" || state ~ / installed$/)) print package "\t" version
            package = ""; version = ""; state = ""
        }
        FNR == 1 { emit() }
        /^Package:/ { emit(); package = $2 }
        /^Version:/ { version = $2 }
        /^Status:/ { state = $0 }
        /^$/ { emit() }
        END { emit() }
    ' $status | LC_ALL=C sort -u | while IFS="$(printf '\t')" read -r package version; do
        [ -n "$version" ] || fail "The package $package in '$dpkg' has no version."
        echo "$package $version"
        echo "  Licence: /usr/share/doc/$package/copyright"
        echo
        component base "$package" "$version" NOASSERTION "/usr/share/doc/$package/copyright"
    done
}

# Every SPDX id the list form names: the expressions split at their operators and parentheses. The GNU Lesser General
# Public License version 3 asks for the GNU General Public License version 3 beside it, so naming one names both.
named_ids() {
    awk -F '\t' 'NF >= 4 { print $4 }' "$1" | tr '()' '  ' | tr ' ' '\n' |
        grep -Ev '^(AND|OR|WITH|NOASSERTION|LicenseRef-.*)?$' | awk '{ print } /^LGPL-3\.0-/ { print "GPL-3.0-only" }' | LC_ALL=C sort -u
}

licence_texts() {
    [ $# -eq 0 ] || usage
    [ -n "${NOTICES_COMPONENTS:-}" ] && [ -f "$NOTICES_COMPONENTS" ] || fail "NOTICES_COMPONENTS names no list. Write the other parts first, each with NOTICES_COMPONENTS set to the same file."
    echo "Licence texts"
    echo "============="
    echo
    echo "The standard text of each licence the entries above name, from the SPDX licence list."
    echo
    for id in $(named_ids "$NOTICES_COMPONENTS"); do
        [ -f "$texts/$id.txt" ] || fail "The licence '$id' that $(awk -F '\t' -v id="$id" 'index(" " $4 " ", id) { print $1 " component " $2 " " $3; exit }' "$NOTICES_COMPONENTS") names has no standard text in licenses/texts. Add the SPDX licence list's text for it at the tag licenses/README.md names."
        echo "$id"
        echo "$id" | sed 's/./-/g'
        echo
        awk '{ sub(/\r$/, ""); sub(/[ \t]+$/, ""); print }' "$texts/$id.txt"
        echo
    done
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
    nuget) [ $# -ge 1 ] || usage; nuget "$@" ;;
    npm) [ $# -eq 1 ] || usage; npm_packages "$1" ;;
    jdk) [ $# -eq 2 ] || usage; jdk "$1" "$2" ;;
    artefact) artefact "$@" ;;
    source) compiled_source "$@" ;;
    launcher) launcher "$@" ;;
    go-modules) [ $# -eq 1 ] || usage; go_modules "$1" ;;
    go) go_part "$@" ;;
    base) base "$@" ;;
    texts) licence_texts "$@" ;;
    *) usage ;;
esac
