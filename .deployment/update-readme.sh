#!/bin/bash

# Update the project readme.md file with the latest set of WordPress plugins
# and themes installed via composer

README_FILE="README.md"
PARSED_DATA="${1}"

table_output="| Plugin | Version |\n"
table_output+="|--------|---------|\n"

while IFS= read -r line; do
  name=$(echo "$line" | jq -r '.name')
  version=$(echo "$line" | jq -r '.version')
  slug=$(echo "$line" | jq -r '.slug')

  if [[ $name == wpackagist-plugin/* ]]; then
    link="https://wordpress.org/plugins/$slug/"
  elif [[ $name == wpackagist-theme/* ]]; then
    link="https://wordpress.org/themes/$slug/"
  else
    homepage=$(echo "$line" | jq -r '.homepage // empty')
    author_homepage=$(echo "$line" | jq -r '.author.homepage // empty')
    link="${homepage:-$author_homepage}"
  fi

  if [[ -z $link ]]; then
    table_output+="| $slug | $version |\n"
  else
    table_output+="| [$slug]($link) | $version |\n"
  fi
done < <(echo "${PARSED_DATA}" | jq -c '.[] | select(.type == "wordpress-plugin" or .type == "wordpress-theme")')

# Replace the content between the comments in the Markdown file
sed -i.bak -e "/<!-- x-linchpin-process-readme-start -->/,/<!-- x-linchpin-process-readme-end -->/c\\<!-- x-linchpin-process-readme-start -->\n$table_output\n<!-- x-linchpin-process-readme-end -->" "$README_FILE"

# Remove the backup file created by sed
rm "${README_FILE}.bak"
