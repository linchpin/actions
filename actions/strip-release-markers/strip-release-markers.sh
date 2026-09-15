#!/usr/bin/env bash
#
# Remove release-please marker lines from files that ship.
#
# release-please brackets the version strings it owns with marker comments:
#
#   x-release-please-start-version
#   Stable tag: 3.0.3
#   x-release-please-end
#
# In a PHP file those are ordinary comments and harmless. In readme.txt they
# are not. WordPress.org and Plugin Check both read the header block as
# contiguous "Key: value" lines and stop at the first line that is not one, so
# a marker sitting mid-block hides every header below it. A plugin with the
# markers still in place was reported as having no Stable tag and no License
# even though both were there, three lines further down.
#
# Usage: strip-release-markers.sh <file> [file...]

set -euo pipefail

if [ "$#" -eq 0 ]; then
	echo "::error::strip-release-markers: no files given"
	exit 1
fi

status=0

for file in "$@"; do
	if [ ! -f "$file" ]; then
		# Not a warning. The caller named a file that ships; if it is not
		# there, the release is not what the caller thinks it is.
		echo "::error::strip-release-markers: no such file: ${file}"
		status=1
		continue
	fi

	before=$(grep -c 'x-release-please' "$file" || true)

	if [ "$before" -eq 0 ]; then
		echo "strip-release-markers: ${file} has no markers, leaving it alone"
		continue
	fi

	# Written to a temp file and moved rather than sed -i, whose in-place flag
	# takes a mandatory argument on BSD sed and none on GNU sed. This runs the
	# same way on a runner and on a laptop.
	tmp="$(mktemp)"
	grep -v 'x-release-please' "$file" > "$tmp"
	cat "$tmp" > "$file"
	rm -f "$tmp"

	echo "strip-release-markers: removed ${before} marker line(s) from ${file}"
done

exit "$status"
