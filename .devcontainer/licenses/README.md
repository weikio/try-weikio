# Licences in the Try Weik.io image

The image this folder's Dockerfile builds holds the same files as the Weik.io images `weikio/weikio-backend`,
`weikio/weikio-apim`, `weikio/weikio-agent` and `weikio/weikio-forwarder`:

- `/LICENSE`: the Apache License 2.0, the licence of Weik.io's own programs.
- `/NOTICE`: the source code offer and the statements of where the source code of the components under a copyleft
  licence is published.
- `/THIRD-PARTY-NOTICES.txt`: every component of others the image holds, each with its licence, the licence and notice
  files the component ships copied in full, and for a component under the Eclipse, Mozilla or Common Public License the
  address of its source code. The standard text of every licence an entry names is at the end of the file.
- `/licenses/components.tsv`: the same components, one per line, with five fields separated by tabs: the part of the
  notices that lists it (`nuget`, `npm`, `jdk`, `artefact`, `source`, `launcher`, `go` or `base`), its name, its
  version, its licence as an SPDX expression (`NOASSERTION` for a distribution package, whose licence is its copyright
  file), and where that licence's text is: `entry` when the component's own files are copied under its entry, `end`
  when it is the standard text at the end of the notices, or a path in the image.
- `/licenses/jdk/` and `/licenses/rclone/COPYING`: the Java runtime's `legal/` tree and rclone's licence.
- `/licenses/<program>.modules`: the module list of each Go program the image adds.
- `/licenses/README.md`: this file.

The notices also list the programs the image copies in from the other images: the agent's and the gateway's NuGet
packages, the `weikio` CLI's, and nats-server and the VictoriaLogs, VictoriaMetrics and VictoriaTraces programs with every
Go module each is built from.

## This folder

- `LICENSE` and `NOTICE`: the files the image holds at `/LICENSE` and `/NOTICE`.
- `notices.sh` and `third-party-notices.sh`: the Dockerfile's `notices` stage writes the image's notices with them, from
  the files the image holds.
- `cli.txt` and `cli.tsv`: the NuGet packages of the release's `weikio` CLI, read from the deps.json of its build, because
  the image takes the CLI as the published file.
- `licence-reviews.txt`: the licence of each component whose own files don't name one, by exact version.
- `texts/`: the standard text of each licence the notices name, one file per SPDX id, copied unchanged from the SPDX
  licence list at the tag `v3.29.0` (https://github.com/spdx/license-list-data/tree/v3.29.0/text).
