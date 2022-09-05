# Linchpin Shared Project Configs
An open source collection of Linchpin's configs. Primarily used for [Renovate bot](https://github.com/marketplace/renovate) and shared workflows. While there are some aspects of this repo that are specific to [Linchpin](https://linchpin.com) and our build process. Other organizations can take advantage of them want to use them.

![license](https://img.shields.io/github/license/linchpin/actions)

## Github Reusable Workflows

Below are resuable/shared workflows. In the coming weeks we will be adding some examples on how to utilize these workflows. They are relative straight forward so if you are used to actions and workflows you can use these as a starting point

| File                                                               | Status                                                                 | Requirements         | description                                                                                                                                     |
|--------------------------------------------------------------------|------------------------------------------------------------------------|----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| [create-release.yml](.github/workflows/create-release.yml)         | ![Active Status](https://img.shields.io/badge/In%20Use-Active-green)   |                      | Create release workflow. Downloads all assets, and runs through the build process creating a single zip. Typically used during a tagged release |
| [deploy-**wpengine**.yml](.github/workflows/deploy-wpengine.yml)   | ![Active Status](https://img.shields.io/badge/In%20Use-Not%20Yet-grey)                                                                       | SSH Access, SSH Key Pair | Deploy to a [WP Engine](https://wpengine.com) platform based environment                                                                        |
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


## More Useful Configs

| File                                     | Description                                                                                                                    |
|------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| [default.distignore](default.distignore) | Default .distignore be loaded during deployment (and renamed to .distignore) if no .distignore is provided within your proejct |

![Linchpin](https://raw.githubusercontent.com/linchpin/brand-assets/master/github-banner@2x.jpg)
