# Repository Guidelines

## Project Structure & Module Organization

`src/` contains the Erlang/OTP server, including LoRaWAN protocol, gateway, database, administration, and backend connector modules. Shared headers live in `include/`; EUnit tests and test helpers are in `test/`. The administration UI source is under `admin/`, while static runtime assets are served from `priv/admin/`. Operational scripts and packaging files are in `scripts/`; setup, API, architecture, and troubleshooting documentation is in `doc/`. Runtime configuration is in `lorawan_server.config`.

## Build, Test, and Development Commands

- `make build` runs `rebar3 compile` and builds the Erlang application. The compile hooks also install the UI dependencies and copy required browser assets.
- `make test` runs the EUnit suite through `rebar3 eunit`.
- `make release` creates a runnable release under `_build/default/rel/lorawan-server`.
- `make clean` removes build output and `node_modules`.

The project requires Erlang/OTP 21 or newer. Read `doc/Installation.md` and `doc/Configuration.md` before running a local server; configure dependencies and credentials in the local runtime configuration rather than committing secrets.

## Coding Style & Naming Conventions

Follow the surrounding Erlang style: use lowercase `snake_case` for modules and functions, `CamelCase` for variables, and descriptive atoms and records. Keep changes focused in the module responsible for the behavior; add shared declarations to `include/` only when needed across modules. Match existing indentation and formatting in the touched file. No repository-wide formatter or lint command is configured.

## Testing Guidelines

Add or update EUnit coverage in `test/` for behavior changes, following the existing `*_tests.erl` or `test_*.erl` naming patterns. Run `make test` before submitting changes when the environment supports the project dependencies. For protocol or gateway changes, use the existing forwarder and mote test helpers where appropriate.

## Commit & Pull Request Guidelines

Recent history uses short, imperative subjects (for example, “Fix …” or “Update …”); some commits include an issue or pull request number. Keep commit subjects concise and describe the change. PRs should explain the problem and solution, link the relevant issue when available, and include reproduction steps and relevant log excerpts for bug fixes. Read `CONTRIBUTING.md` and the applicable documentation before requesting review.
