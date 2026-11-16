@AGENTS.md

## Claude Code specifics

- Prefer reading [docs/STATUS.md](docs/STATUS.md) and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
  before running experiments; most investigations have already been done and recorded there.
- Build/test with the commands in AGENTS.md; `swift test` needs no tablet.
- Hardware tests need the user at the tablet. Ask them to perform an action, then read the result from
  `--dump` / `--verbose` output or a listen-only CGEvent tap instead of guessing.
