# Contributing

Thank you for your interest in improving `android_chroot_env`.

This project is currently maintained as an Android + Magisk + chroot environment module with optional Hermes integration. Contributions are welcome, especially around reliability, documentation, compatibility, and service management.

## Recommended contribution areas

- Installation and initialization reliability
- RootFS bootstrap improvements
- Android / Magisk compatibility fixes
- Hermes integration workflow improvements
- Documentation quality and examples
- Service startup, SSH, and autostart enhancements
- Logging, diagnostics, and recovery behavior

## Before contributing

Please make sure that:
- You understand the risks of modifying Magisk modules on rooted Android devices
- You test carefully before publishing changes intended for boot-time execution
- You clearly document behavior changes affecting initialization, mounting, autostart, or Hermes integration

## Development suggestions

When making changes, try to keep the following stable:
- Module layout and upgrade path
- Existing command names such as `chroot-env ...`
- Configuration file semantics where possible
- Backward compatibility for common user workflows

## Pull request guidelines

If you submit a pull request, please:

1. Describe the problem being solved
2. Summarize the implementation approach
3. Mention any behavior changes or migration considerations
4. Include testing notes
5. Keep documentation updated when commands, paths, or behavior change

## Suggested PR checklist

- [ ] Change is scoped and clearly described
- [ ] Boot-time behavior was considered and tested
- [ ] Documentation was updated if needed
- [ ] Release-impacting changes are noted in `CHANGELOG.md`
- [ ] Commands and paths were validated on a real or representative environment

## Reporting issues

When opening an issue, it helps to include:
- Android version
- Magisk version
- Device architecture
- Whether RootFS was initialized successfully
- Relevant command output
- Relevant logs from the module or Hermes gateway

## Code and docs style

- Prefer clear, operational documentation
- Keep examples practical and copyable
- Avoid breaking existing workflows without strong reason
- Favor explicit paths and reproducible commands over vague descriptions

## Security note

Do not publish secrets, tokens, or private device-specific credentials in issues or pull requests.
