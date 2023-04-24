#!/bin/bash

# Update the project readme.md file with the latest set of WordPress plugins
# and themes installed via composer
#

README_FILE="README.md"
PARSED_DATA="${1}"

table_output="| Plugin | Version |\n"
table_output+="|--------|---------|\n"

table_output+=$(echo "${PARSED_DATA}" | jq -r '.[] | select(.type == "wordpress-plugin") | "| \(.slug) | \(.version) |"')

# Check if both comments exist in the README.md file
if grep -q "<!-- x-linchpin-process-readme-start -->" "$README_FILE" && grep -q "<!-- x-linchpin-process-readme-end -->" "$README_FILE"; then
  # Replace the content between the comments in the Markdown file
  sed -i.bak -e "/<!-- x-linchpin-process-readme-start -->/,/<!-- x-linchpin-process-readme-end -->/c\\<!-- x-linchpin-process-readme-start -->\n$table_output\n<!-- x-linchpin-process-readme-end -->" "$README_FILE"

  # Remove the backup file created by sed
  rm "${README_FILE}.bak"
else
  echo "Error: The required comments are missing in the README.md file."
  exit 1
fi
