#!/bin/bash

# Update the project readme.md file with the latest set of WordPress plugins
# and themes installed via composer

README_FILE="README.md"
COMPOSER_LOCK_FILE="composer.lock"
TEMP_FILE="table_output.tmp"

# Update the release date
current_date=$(date +"%m/%d/%Y")
awk -v date="$current_date" '
  {
    if ($0 ~ /<!-- x-linchpin-release-date-start -->/) {
      sub(/<!-- x-linchpin-release-date-start -->.*<!-- x-linchpin-release-date-end -->/, "<!-- x-linchpin-release-date-start -->" date "<!-- x-linchpin-release-date-end -->")
    }
    print
  }
' "$README_FILE" > temp && mv temp "$README_FILE"

# Check if composer.lock file exists and update if it exists
if [[ ! -f "$COMPOSER_LOCK_FILE" ]]; then
  echo "Note: $COMPOSER_LOCK_FILE not found."
else
  # Every plugin and theme in the lock, whatever its vendor, sorted by the name
  # the table shows. Filtering on wpackagist and linchpin names dropped every
  # wp-plugin/* and wp-theme/* package once sites moved to wp-packages.org.
  table_output=$(jq -r '
      [.packages[] | select(.type == "wordpress-plugin" or .type == "wordpress-theme")]
      | sort_by(.name | split("/")[1] | ascii_downcase)[]
      | "| \(.name | split("/")[1]) | \(.version) |"
  ' "$COMPOSER_LOCK_FILE")
fi

# Check if the table_output is empty
if [[ -n "$table_output" ]]; then
  # Add table headers
  table_output=$(printf "| Plugin Name | Version |\n|------|---------|\n%s" "$table_output")

  # Write the table_output to a temporary file
  echo "$table_output" > "$TEMP_FILE"

  # Replace the lines between the comments in the Markdown file, line by line.
  # This read the README in paragraph mode (RS = "") and wrote it back with
  # ORS = "\n", which deleted every blank line in the file on every release:
  # linchpin.com's README had none left in 146 lines. Everything outside the
  # markers is now printed exactly as read. A start marker with no end marker
  # after it leaves the file as it was rather than dropping the rest of it.
  awk -v temp_file="$TEMP_FILE" '
    BEGIN {
      while ((getline line < temp_file) > 0) table = table (table == "" ? "" : "\n") line
      close(temp_file)
    }
    replacing {
      held = held $0 "\n"
      if ($0 ~ /<!-- x-linchpin-plugin-list-end -->/) {
        print table
        print
        replacing = 0
        held = ""
      }
      next
    }
    /<!-- x-linchpin-plugin-list-start -->/ {
      if ($0 ~ /<!-- x-linchpin-plugin-list-end -->/) {
        sub(/<!-- x-linchpin-plugin-list-start -->.*<!-- x-linchpin-plugin-list-end -->/, "<!-- x-linchpin-plugin-list-start -->\n" table "\n<!-- x-linchpin-plugin-list-end -->")
        print
        next
      }
      print
      replacing = 1
      held = ""
      next
    }
    { print }
    END { if (replacing) printf "%s", held }
  ' "$README_FILE" > temp && mv temp "$README_FILE"
fi

if [[ -f "$TEMP_FILE" ]]; then
  # remove the temporary file
  rm "$TEMP_FILE"
fi
