# Try Weik.io

[![Open in Dev Containers](https://img.shields.io/static/v1?label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/weikio/try-weikio)

This repository opens in a development container that runs all of Weik.io on your machine. You type only `weikio` commands to create an integration, run it on the platform, read its logs or run it locally with Camel. The same steps are on https://weik.io/try, next to the University video that shows them.

## What you need

- Docker: Docker Engine on Linux, or Docker Desktop on Windows or macOS. Give Docker 8 GB of memory (6 GB at least), 4 CPUs and 20 GB of free disk.
- Visual Studio Code with the Dev Containers extension, or the `devcontainer` command line (`npm install -g @devcontainers/cli`).
- Internet access for the first build of the container, which downloads the platform's images from Docker Hub, the `weikio` CLI from weik.io, Ubuntu packages and the Go modules the image's licence notices list. The first build of an integration and the first local run fetch Camel's libraries from Maven Central. Later runs use the copies kept in the container.

The platform's images are built for Intel and AMD processors. On a Mac with Apple silicon, Docker runs them emulated, which is slower.

## Open it

Click **Open in Dev Containers** above, or clone the repository and open it in Visual Studio Code:

```sh
git clone https://github.com/weikio/try-weikio
code try-weikio
```

Then run **Dev Containers: Reopen in Container**. The first time, the image is built, which takes a few minutes. Setting up the platform then takes less than a minute, and the terminal shows:

```
Weik.io 2026.2.2 is running in this container.

Admin UI:  http://localhost:8580 (Chrome, Edge or Firefox)
Admin:     admin@local, who signs in with a password
CLI:       signed in as the platform admin, in project sandbox and environment devtest
```

`"WEIKIO_ANIMATION": "off"` in the devcontainer's `remoteEnv` turns off the animation the terminal shows before these lines. From the command line, start the container with `devcontainer up --workspace-folder .` and open a shell in it with `devcontainer exec --workspace-folder . bash`. The command line forwards no port, so before you open the admin UI, run `node .devcontainer/forward-admin-ui.js` on your machine in the same folder and leave it running.

## Try it

Create an integration in `./hello` that logs a line every 5 seconds:

```
$ weikio init hello
Created hello/
  hello.camel.yaml        timer -> log, runs every 5 s
  application.properties  message=hello from weikio
  integration.yaml        name hello, other fields as commented examples

Next, to run it in project sandbox and environment devtest:
  weikio run ./hello
```

Publish it, deploy it to devtest and follow its log lines. Ctrl-C stops following, and the integration keeps running:

```
$ weikio run hello
Target: http://localhost:8580, project sandbox (context), environment devtest (context)
Uploading 3/3 files, building...
integration sandbox/hello created (version 0.1.0, built in 16.2 s)
deployment devtest/sandbox/hello created (follows latest)
Following the log lines of sandbox/hello. Ctrl-C stops following, and the integration keeps running.
09:14:06.095 UTC INFO  dev  Apache Camel (Main) 4.22.1 is starting
...
09:14:06.439 UTC INFO  dev      Started hello (timer://tick)
09:14:07.113 UTC INFO  hello  dev  Exchange[ExchangePattern: InOnly, BodyType: String, Body: hello from weikio]
09:14:12.114 UTC INFO  hello  dev  Exchange[ExchangePattern: InOnly, BodyType: String, Body: hello from weikio]
```

See where it runs and in what state:

```
$ weikio status sandbox/hello
ENVIRONMENT   VERSION          STATE     AGENT   SINCE                  DETAIL
devtest       0.1.0 (latest)   running   dev     2026-10-24 09:14 UTC   -

Last hour in devtest: 30 messages, 0 failed (0 %), memory 124 MB.
```

Read its log lines:

```
$ weikio logs sandbox/hello
...
09:14:07.113 UTC INFO  hello  dev  Exchange[ExchangePattern: InOnly, BodyType: String, Body: hello from weikio]
09:14:12.114 UTC INFO  hello  dev  Exchange[ExchangePattern: InOnly, BodyType: String, Body: hello from weikio]
```

Run the same folder here with Camel and devtest's values, before you publish a change:

```sh
weikio dev run hello
```

`weikio init` writes into this folder, so the integration's files are on your machine and in your editor. Edit `hello/hello.camel.yaml` or the message in `hello/application.properties` and run `weikio run hello` again to publish and deploy the change as version 0.1.1.

## The admin UI

Open http://localhost:8580. The admin is `admin@local`, and it has no password until you choose one:

1. In the container's terminal, run `weikio-dev ui-link`, which prints a one-time link.
2. Open the link in your browser, on the machine where your editor runs, and choose a password.
3. That signs you in. Later you sign in with `admin@local` and that password.

The admin signs in with the password alone, because this container turns off the two-factor sign-in that an installation requires of its platform administrators by default. The admin UI and `weikio problems` show a warning about it. To require a code from an authenticator app, as a production installation does, run `weikio settings set --two-factor-required=true`.

Use Chrome, Edge or Firefox, because Safari may refuse the sign-in on `http://localhost`. The port must be 8580 on your machine as well, because the platform's own address is http://localhost:8580. If something else uses 8580, VS Code forwards the next free port without a warning, and its Ports view shows which. Stop what uses 8580 and reopen the container.

## When something is wrong

```
weikio-dev status          every process of the platform: up or down, restarts, health check
weikio-dev logs            the list of logs, and weikio-dev logs backend -f follows one
weikio-dev wait            follow the platform's start until it is ready
weikio-dev reset           remove the installation and set up a new one, which loses every integration
```

The installation is kept in a Docker volume, so it survives a restart and a rebuild of the container. Removing the volume, or `weikio-dev reset`, starts from nothing.

Everything runs on plain HTTP inside the container and listens only on the container's own loopback address. The platform admin's API key is kept in the container's data volume, readable only by the container's user. This setup is for trying Weik.io on your own machine, and installing on a server is described in https://weik.io/docs/operate/install-single-server.

## Next

- The first integration guide with the Camel 1 video: https://weik.io/docs/start/first-integration
- Back to Try Weik.io: https://weik.io/try

## Links

- Weik.io: https://weik.io
- Docs: https://weik.io/docs
- University: https://weik.io/university
- Weik.io Cloud: https://weikio.cloud
- Live demo: https://demo.weik.io
- GitHub: https://github.com/weikio/weikio
