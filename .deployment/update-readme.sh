#!/bin/bash

# Update the project readme.md file with the latest set of WordPress plugins
# and themes installed via composer

README_FILE="README.md"
COMPOSER_LOCK_FILE="composer.lock"

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
table_output="| Name | Version |\n|------|---------|\n$table_output"

# Replace the content between the comments in the Markdown file
sed -i.bak -e "/<!-- x-linchpin-process-readme-start -->/,/<!-- x-linchpin-process-readme-end -->/c\\<!-- x-linchpin-process-readme-start -->\n$table_output\n<!-- x-linchpin-process-readme-end -->" "$README_FILE"

# Support for additional comment tags
sed -i.bak -e "/<!-- x-linchpin-update-readme-start -->/,/<!-- x-linchpin-update-readme-end -->/c\\<!-- x-linchpin-update-readme-start -->\n$table_output\n<!-- x-linchpin-update-readme-end -->" "$README_FILE"

# Support for plugin list
sed -i.bak -e "/<!-- x-linchpin-plugin-list-start -->/,/<!-- x-linchpin-plugin-list-end -->/c\\<!-- x-linchpin-plugin-list-start -->\n$table_output\n<!-- x-linchpin-plugin-list-end -->" "$README_FILE"

# Update the release date
current_date=$(date +"[%m/%d/%Y]")
sed -i.bak -e "/<!-- x-linchpin-release-date-start -->/,/<!-- x-linchpin-release-date-end -->/c\\<!-- x-linchpin-release-date-start -->$current_date<!-- x-linchpin-release-date-end -->" "$README_FILE"

# Remove the backup file created by sed
rm "${README_FILE}.bak"