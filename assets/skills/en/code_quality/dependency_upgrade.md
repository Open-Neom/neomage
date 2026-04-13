# Dependency Upgrade

Manage major dependency version upgrades with compatibility analysis, staged rollout, and comprehensive testing.

- Read changelogs and migration guides before upgrading; understand breaking changes
- Upgrade incrementally: one major version at a time, one dependency at a time
- Test after each upgrade: unit, integration, E2E, and visual regression
- Resolve peer dependency conflicts early; use lock files for reproducible installs
- Use codemods and automated migration scripts where available
- Automate routine updates with Renovate or Dependabot; auto-merge minor/patch
- Always have a rollback plan: branch, tag, or lock file restore
- Monitor for runtime errors post-upgrade in staging before production
