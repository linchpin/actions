# Linchpin Shared Project Configs
An open source collection of Linchpin's configs. Primarily used for [Renovate bot](https://github.com/marketplace/renovate) and shared workflows. While there are some aspects of this repo that are specific to [Linchpin](https://linchpin.com) and our build process. Other organizations can take advantage of them want to use them.

![license](https://img.shields.io/github/license/linchpin/actions) ![version](https://img.shields.io/badge/version-v3-black)

## Major Differences in v3 of the Github Reusable Workflows

Version 3 of is a shift towards removing Organizational, Repo and Environment level Variables out of the workflow
files and being defined within the GitHub interface. This allows for more flexibility within our deployments process
including the ability to overide variables at each level as needed.

## Github Secrets and Variables

Below is a list of standard secret and variables used in Linchpin's shared workflows

### Secrets

To learn more [about secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions) in your workflows please see GitHubs great documentation.

| Key        | Default | Description |
| ---------- | ------- | ----------------------------------------------------------------- |
| SSH_KEY    |         | The SSH key used to interact w/ the remote environment            |
| SSH_USER   |         | The SSH user used to interact w/ the remote environment           |
| SSH_PASS   |         | THe SSH pass used for environments that cannot support SSH Keys (Cloudways Autonomous) |
| SSH_HOST   |         | The SSH IP or Host Name |
| SATISPRESS_USER | | Authenticate with Private Packagist |
| SATISPRESS_PASSWORD | | Authenticate with Private Packagist |
| PACKAGIST_COMPOSER_AUTH_JSON | | Alternative Authentication with Private Packagist |
 
### Variables

To learn more [about variables](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables) in your workflows please see GitHubs great documentation.

| Key | Default | Description |
| --- | ------- | ----------- |
| HOST    |         | The host of the project, typically one of (pressable, cloudways, pantheon, wpengine )             |
| ENVIRONMENT | staging | The environment type we are pushing to |
| SITE_URL | | The url of the site including http:// |
| SITE_ID | | When using **Pressable** this is how we reference a site |
| DEPLOYMENT_AUTH_TYPE | key | The deploy type on the environment |
| DEPLOYMENT_PATH | | The initial folder the release it uploaded to,the default is different per provider. See each individial `deploy{{host}}.yml` for an example. |
| REMOTE_PLUGIN_INSTALL | false | Whether or not to use the WP CLI to install and/or update plugins on the remote environment instead of using linchpin.packagist.com or wpackagist.org |
| BRANCH | staging | The default branch associated with the workflow, this is also impacted by Environment Setup in GitHub |
| INSTALL_NAME | | Install name when project is hosted on WP Engine |
| THEMES | | A JSON formatted array of themes to build Ex `["linchpin-theme", "linchpin-child-theme"]` |
| PLUGINS | | A JSON formatted array of plugins to build Ex `["linchpin-functionality"]` |
| THEME_USES_COMPOSER | false | Do the theme(s) use composer to load dependencies |
| PLUGIN_USES_COMPOSER | true | Do the plugins(s) use composer to load dependencies |

## Breaking Changes from `main` or `v2`

If you 

## Github Reusable Workflows

Below are resuable/shared workflows. They are relative straight forward so if you are used to actions and workflows you can use these as a starting point

| File                                                               | Status                                                                 | Requirements         | description                                                                                                                                     |
|--------------------------------------------------------------------|------------------------------------------------------------------------|----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| [create-release.yml](.github/workflows/create-release.yml)         | ![Active Status](https://img.shields.io/badge/In%20Use-Active-green)   |                      | Create release workflow. Downloads all assets, and runs through the build process creating a single zip. Typically used during a tagged release |
| [deploy-**pressable**.yml](.github/workflows/deploy-pressable.yml) | ![Active Status](https://img.shields.io/badge/In%20Use-Active-green) | SSH Access, SSH Pass or SSH Key Pair | Deploy to the a Pressable  environment, uses [deploy-**base**.yml](.github/workflows/deploy-base.yml)                                                                                                 |
| [deploy-**wpengine**.yml](.github/workflows/deploy-wpengine.yml)   | ![Active Status](https://img.shields.io/badge/In%20Use-Active-green)                                                                       | SSH Access, SSH Key Pair | Deploy to a [WP Engine](https://wpengine.com) platform based environment                                                                        |
| [deploy-**cloudways**.yml](.github/workflows/deploy-cloudways.yml) | ![Active Status](https://img.shields.io/badge/In%20Use-Active-green) | SSH Access, SSH Key Pair | Deploy to a Cloudways platform  environment                                                                                                     |
| [phpcs.yml](.github/workflows/phpcs.yml)                           | ![Active Status](https://img.shields.io/badge/In%20Use-Active-green)                                           |                      | Scan for WordPress Coding standards based on the phpcs.xml config of the project                                                                |

## Example Shared Workflow Usage

Within your projects **.github/workflows** folder

``` yaml
name: Create Release
on:
  push:
    tags:
      - 'v*' # Push events to matching v*, i.e. v1.0, v20.15.10

jobs:
  create_release:
    name: Create Release
    uses: linchpin/actions/.github/workflows/create-release.yml@main
    with:
      themes: '["my-wordpress-theme"]'
    secrets:
      packagist_auth: ${{ secrets.custom_packagist_auth_key }}
```

## Renovate Bot Scanning Configurations

| File                             | description                                                |
|----------------------------------|------------------------------------------------------------|
| [global.json](global.json)       | Shared global config for renovatebot                       | 
| [wordpress.json](wordpress.json) | Shared config for renovatebot for WordPress installs.      |
| [js.json](js.json)               | Shared config for javascript projects (gulp builds, etc )  |


## Make deployments faster/more automated. Especially when using Smart Plugin Manager, Autopilot, Cloudways Plugin Updates

| File | Description |
| ---- | ----------- |
| [remote-plugin-install](.deployment/remote-plugin-install.php) | A bash script to load plugins via the WP CLI  including a remote satispress packagist |

| [remmote-plugin-install]

## More Useful Configs

| File                                     | Description                                                                                                                    |
|------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| [default.distignore](default.distignore) | Default .distignore be loaded during deployment (and renamed to .distignore) if no .distignore is provided within your proejct |

![Linchpin](https://raw.githubusercontent.com/linchpin/brand-assets/master/github-banner@2x.jpg)
