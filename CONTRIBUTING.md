# Contributing

Thanks for helping. Bug reports, sensor maps for new Macs and code are all welcome.

## Adding your Mac

This is the most useful contribution. Follow [docs/supported-models.md](docs/supported-models.md) to open a report, or add the chip yourself as described in [docs/smc-keys.md](docs/smc-keys.md#adding-a-chip).

## Development

1. Read [docs/architecture.md](docs/architecture.md). It explains which module owns what.
2. Build and run as described in [docs/building.md](docs/building.md).
3. Run `swift test` in `Packages/FanKit` before opening a pull request.
4. Run only one copy of the app at a time; a new copy started from Xcode quits the others, because two copies would fight over the fans.

## Guidelines

- **Logic goes in the package.** Put anything that can be tested in `FanKit` or `SMCKit` and add a test. Rules, curves, limits and formats all live there.
- **Keep the helper minimal.** Changes to `Helper/` or `FanXPC` get extra review, because that code runs as root. Explain in the pull request why the change is needed. The rules in `.semgrep/` check what the helper must never do; run `semgrep scan --test .semgrep` and `semgrep scan --config .semgrep --exclude .semgrep`.
- **Follow the Human Interface Guidelines.** Use system components, semantic colors and SF Symbols. Don't hard-code colors or fonts. Don't carry meaning by color alone.
- **Localize user-facing text.** Add new strings to `App/Resources/Localizable.xcstrings` with an English source and a Turkish translation.
- **Match the existing style.** A `.swiftformat` config is included.

## Pull requests

- Keep each pull request focused on one change.
- Describe what changed and how you tested it, including the Mac model if the change touches the SMC.
- Write commit messages, and the pull request title for squash merges, as [Conventional Commits](https://www.conventionalcommits.org): `fix: …`, `feat: …`, `docs: …`. Releases and `CHANGELOG.md` are generated from them, so describe the change as people using the app see it. Don't edit `CHANGELOG.md` or the version by hand. See [docs/building.md](docs/building.md#releasing).
