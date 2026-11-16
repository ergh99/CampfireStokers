# Automated WoW Addon Releases on CurseForge

Yes. CurseForge has an upload API that takes a per-account API token, and most WoW addon authors drive it from CI. The usual tool is the **BigWigs Packager** running in GitHub Actions: when you push a new tag, GitHub automatically packages a .zip file and uploads it to CurseForge, WoWInterface and GitHub Releases. It can also upload to Wago.

Here's a minimal setup:

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ['*']
jobs:
  release:
    runs-on: ubuntu-latest
    env:
      CF_API_KEY: ${{ secrets.CF_API_KEY }}
      GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: BigWigsMods/packager@v2
```

You also need two things:

- Add `## X-Curse-Project-ID: 12345` to your `.toc` file so the packager knows which CurseForge project to upload to.
- Generate a token at https://wow.curseforge.com/account/api-tokens and save it as a repo secret named `CF_API_KEY`.

After that, `git tag v1.0.0 && git push --tags` publishes the release.

## Other options

- **wow-build-tools**: a newer alternative that is also available as a GitHub Action on the GitHub Marketplace.
- **wap**: a Python tool (`wap publish --curseforge-token ...`).
- Calling the raw CurseForge upload API yourself.

## Sources

- [Using the BigWigs Packager with GitHub Actions – Warcraft Wiki](https://warcraft.wiki.gg/wiki/Using_the_BigWigs_Packager_with_GitHub_Actions)
- [wow-build-tools – CurseForge](https://www.curseforge.com/wow/addons/wow-build-tools)
- [wow-addon-packager (wap) – PyPI](https://pypi.org/project/wow-addon-packager)