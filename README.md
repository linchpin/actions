# Linchpin Share Project Configs
An open source collection of Linchpin's configs. Primarily used for Renovate bot and shared workflows. While there are some aspects of this repo that are specific to Linchpin and our build process. I don't see any problem sharing them with any other organizations that want to use them.

## Renovate Bot

|File| description |
|----|-----------|
| global.json | Shared global config for renovatebot | 
| wordpress.json | Shared config for renovatebot for WordPress installs. |

## Github Workflow Actions

|File| description |
|----| -----------|
| .github/workflows/create-release.yml | Shared create release workflow. Downloads all assets, and runs through the build process creating a single zip. Typically used during a tagged release  |
| .github/workflows/deploy-develop.yml | Deploy to a dev environment |
| .github/workflows/deploy-staging.yml | Deploy to a staging environment |
| .github/workflows/deploy-production.yml | Deploy to a production environment |
| .github/workflows/phpcs.yml | scan for WordPress Coding standards based on the phpcs.xml config of the project |
