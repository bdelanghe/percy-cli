# Percy CLI

[![Test](https://github.com/percy/cli/workflows/Test/badge.svg)](https://github.com/percy/cli/actions)

The Percy CLI is used to interact with, and upload snapshots to, [percy.io](https://percy.io) via
the command line.

- [Installation](#installation)
- [Command Topics](#command-topics)
- [Advanced](#advanced)
- [Issues](#issues)
- [Developing](#developing)

## Installation

```sh-session
$ npm install --save-dev @percy/cli
```

## Command Topics

- [`percy exec`](./packages/cli-exec#readme) - capture and upload snapshots
- [`percy snapshot`](./packages/cli-snapshot#readme) - snapshot a static directory or a list of pages
- [`percy upload`](./packages/cli-upload#readme) - upload a static directory of images
- [`percy config`](./packages/cli-config#readme) - manage configuration files
- [`percy build`](./packages/cli-build#readme) - interact with Percy builds

### Advanced

In addition to the CLI packages, this repo contains core libraries responsible for Percy's CI/CD
integrations, Percy API communication, DOM serialization, asset discovery, etc.

- [`@percy/core`](./packages/core#readme) - performs snapshot asset discovery and uploading
- [`@percy/client`](./packages/client#readme) - handles communicating with the Percy API
- [`@percy/dom`](./packages/dom#readme) - serializes DOM snapshots
- [`@percy/env`](./packages/env#readme) - captures CI build environment variables
- [`@percy/config`](./packages/config#readme) - loads Percy configuration files
- [`@percy/logger`](./packages/logger#readme) - common logger used throughout the CLI
- [`@percy/sdk-utils`](./packages/sdk-utils#readme) - shared helpers for JavaScript SDKs
- [`@percy/cli-command`](./packages/cli-command#readme) - Percy CLI command framework

## Issues

For problems directly related to the CLI, [add an issue on
GitHub](https://github.com/percy/cli/issues/new).

For other issues, [open a support
request](https://www.browserstack.com/contact?ref=percy#technical-support).

## Developing

This project uses Bun for package management and builds. The core libraries and CLI plugins are
located in [./packages](./packages). Run `bun install` to install dependencies after cloning the repo and
use the following scripts for various development tasks:

- `bun run build` - build all packages
- `bun run build:watch` - build and watch all packages in parallel
- `bun run clean` - clean up build and coverage output
- `bun run lint` - lint all packages
- `bun run readme` - generate cli commands readme usage
- `bun test` - run all tests
- `bun test --coverage` - run all tests with coverage
- `bun link` - links all packages being developed as global
    - requires `bun run build` to be run before consuming
    - we can then consume this package using
        `bun link @percy/[core|cli..]`
    - **Note**: linking is only required once, subsequent changes for development requires running build command. 
    
- `bun unlink` - unlinks all packages globally

Individual package scripts can be invoked using Bun's workspace filtering. For example:

```sh-session
$ bun run --filter '@percy/core' test
```

### How to update Chromium revision?

check in Core Package's readme [here](./packages/core#readme).
