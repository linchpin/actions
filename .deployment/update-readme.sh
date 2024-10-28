#!/bin/bash

# Update the project readme.md file with the latest set of WordPress plugins
# and themes installed via composer

README_FILE="README.md"
COMPOSER_LOCK_FILE="composer.lock"
TEMP_FILE="table_output.tmp"

# Check if composer.lock file exists
if [[ ! -f "$COMPOSER_LOCK_FILE" ]]; then
  echo "Error: $COMPOSER_LOCK_FILE not found."
  exit 1
fi

# Extract relevant packages and build the markdown table
table_output=$(jq -r '
    .packages[] |
    select((.name | contains("wpackagist") or contains("linchpin")) and
           (.type == "wordpress-plugin" or .type == "wordpress-theme")) |
    "| \(.name | split("/")[1]) | \(.version) |"
' "$COMPOSER_LOCK_FILE")

# Check if the table_output is empty
if [[ -z "$table_output" ]]; then
  echo "Error: No relevant packages found."
  exit 1
fi

# Add table headers
table_output=$(printf "| Plugin Name | Version |\n|------|---------|\n%s" "$table_output")

# Write the table_output to a temporary file
echo "$table_output" > "$TEMP_FILE"

# Replace the content between the comments in the Markdown file
awk -v temp_file="$TEMP_FILE" '
  BEGIN { RS = ""; ORS = "\n" }
  {
    if ($0 ~ /<!-- x-linchpin-plugin-list-start -->/) {
      while ((getline line < temp_file) > 0) {
        sub(/<!-- x-linchpin-plugin-list-start -->.*<!-- x-linchpin-plugin-list-end -->/, "<!-- x-linchpin-plugin-list-start -->\n" line "\n<!-- x-linchpin-plugin-list-end -->")
      }
      close(temp_file)
    }
    print
  }
' "$README_FILE" > temp && mv temp "$README_FILE"

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
