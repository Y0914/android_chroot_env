# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows semantic-style version tags where practical.

## [v1.2.0] - 2026-04-13

### Added
- Initial public repository setup
- Formal project README
- GitHub Release for `v1.2.0`
- Release asset upload: `android_chroot_env-v1.2.0-release.zip`
- Magisk module packaging for Android chroot environment deployment
- RootFS download and initialization workflow
- `chroot-env` command entrypoints for shell, exec, status, init, and unmount operations
- Hermes integration entrypoints for install, setup, model/tools configuration, diagnostics, and gateway startup
- API Server / Gateway related configuration support
- Boot-time service hook support through module scripts

### Notes
- Current target architecture is `arm64`
- Default RootFS source is Ubuntu Base 26.04 beta arm64
- This release is experimental and intended for advanced users familiar with Magisk, root, and chroot workflows
