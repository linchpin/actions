# Changelog

## [4.2.2](https://github.com/linchpin/actions/compare/v4.2.1...v4.2.2) (2026-06-19)


### Bug Fixes

* publish release with GH_BOT_TOKEN so release:published triggers deploys ([#127](https://github.com/linchpin/actions/issues/127)) ([0758783](https://github.com/linchpin/actions/commit/07587838dce6a5b0873c8ce13a489845a6ebaaa3))

## [4.2.1](https://github.com/linchpin/actions/compare/v4.2.0...v4.2.1) (2026-06-17)


### Bug Fixes

* validate composer lock with install, not validate (version-field churn) ([#125](https://github.com/linchpin/actions/issues/125)) ([9e96999](https://github.com/linchpin/actions/commit/9e969994a2c34d1da444e27b6e9a179942d28730))

## [4.2.0](https://github.com/linchpin/actions/compare/v4.1.0...v4.2.0) (2026-06-17)


### Features

* publish release after asset attach (draft-safe) and trim deploy wait ([#123](https://github.com/linchpin/actions/issues/123)) ([f57f453](https://github.com/linchpin/actions/commit/f57f4533fac01d776da65b9c0f2b9e823b644651))

## [4.1.0](https://github.com/linchpin/actions/compare/v4.0.2...v4.1.0) (2026-06-17)


### Features

* add composer validate gate to catch lock drift early ([#121](https://github.com/linchpin/actions/issues/121)) ([b40b626](https://github.com/linchpin/actions/commit/b40b6261c770b55958744b960444d0485184fff8))

## [4.0.2](https://github.com/linchpin/actions/compare/v4.0.1...v4.0.2) (2026-06-13)


### Bug Fixes

* wait for release.zip asset before deploying (asset/deploy race) ([4f116cd](https://github.com/linchpin/actions/commit/4f116cdd67739204ac0890dcab35254af1b2e87e))

## [4.0.1](https://github.com/linchpin/actions/compare/v4.0.0...v4.0.1) (2026-06-12)


### Bug Fixes

* drop environment binding from the build job ([63fd313](https://github.com/linchpin/actions/commit/63fd313aef5ab74a9736ee146d6c7a7cd62368da))
* use exact-match git/ref endpoint for the floating major tag check ([0b52a61](https://github.com/linchpin/actions/commit/0b52a619d932d604b874ac69e856be83b9fe1253))

## [4.0.0](https://github.com/linchpin/actions/compare/v3.0.0...v4.0.0) (2026-06-12)


### ⚠ BREAKING CHANGES

* **v4:** single-job build, asset-based deploy, consolidated lint
* **v4:** add composite actions for setup, build, deploy, and readme

### Features

* **v4:** add composite actions for setup, build, deploy, and readme ([73bacb4](https://github.com/linchpin/actions/commit/73bacb4a249bff0ac17cfbdffef611cf9443a60e))
* **v4:** restore backup/continue flow and WP Engine + Cloudways hosts ([b05c15d](https://github.com/linchpin/actions/commit/b05c15de29992da91f566b5a508a9955f5ae61fe))
* **v4:** single-job build, asset-based deploy, consolidated lint ([97aec37](https://github.com/linchpin/actions/commit/97aec374b7cba7b4ea8a11b6c0ffa8040e8c69f9))
* **v4:** wire real releases — release-please + floating major tags ([79d7348](https://github.com/linchpin/actions/commit/79d7348240a0da06e913b644df4f136e24dde308))
