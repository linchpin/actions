---
title: strip-release-markers
---

`strip-release-markers` deletes every line containing `x-release-please` from the files you name, `readme.txt` by default, so release-please's version markers never reach WordPress.org or a release archive as literal text. Use it in a plugin's own build, on the copy that ships.

## Why readme.txt breaks

release-please brackets the version strings it owns with marker lines:

```text
x-release-please-start-version
Stable tag: 3.0.3
x-release-please-end
```

In a PHP file those are harmless comments. In `readme.txt` they are not: the WordPress.org readme parser and Plugin Check read the header block as contiguous `Key: value` lines and stop at the first line that is not one. A marker between `Requires PHP` and `Stable tag` hides `Stable tag`, `License` and `License URI`, which surfaces as the `no_stable_tag` and `no_license` errors on a readme that declares both.

## Example

```yaml
- uses: linchpin/actions/actions/strip-release-markers@v4
  with:
    files: |
      build/my-plugin/readme.txt
```

Point it at the built copy, after the files are copied and before they are zipped. No shared workflow in this repository calls it.

## Behaviour to know

- **Whole lines go.** Any line containing `x-release-please` is removed, whatever else is on it. Run it only on files whose markers sit on lines of their own, and never on the working copy release-please reads.
- **A missing file fails the step.** It logs `strip-release-markers: no such file: <file>`, processes the rest, and exits non-zero: a file you expect to ship that is not there means the release is not what you think it is.
- **A file without markers is left alone.**
- **`files` is split on whitespace**, so names containing spaces are not supported.
- **It runs the same on a laptop.** It rewrites through a temp file rather than `sed -i`, whose flag differs between BSD and GNU sed: `bash actions/strip-release-markers/strip-release-markers.sh readme.txt`.

## Inputs

<!-- wp:docspress/fields {"title":"Inputs","fields":[{"name":"files","type":"string","required":false,"defaultValue":"readme.txt","description":"Whitespace or newline separated list of files to strip","values":"","deprecated":false}],"searchable":false,"compact":false} /-->

## Source

[`action.yml`](https://github.com/linchpin/actions/blob/main/actions/strip-release-markers/action.yml), [`strip-release-markers.sh`](https://github.com/linchpin/actions/blob/main/actions/strip-release-markers/strip-release-markers.sh)
