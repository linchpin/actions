#!/bin/bash

# Update the project readme.md file with the latest set of WordPress plugins
# and themes installed via composer

README_FILE="README.md"
PARSED_DATA="${1}"

output_data="["

# Read the composer.lock file and loop through each package
jq '.packages[]' composer.lock | while read -r package; do
  # Extract the name, type, and version from the package
  name=$(echo "$package" | jq -r '.name')
  type=$(echo "$package" | jq -r '.type')
  version=$(echo "$package" | jq -r '.version')

  # Check if the type is wordpress-plugin or wordpress-theme
  if [[ "$type" == "wordpress-plugin" || "$type" == "wordpress-theme" ]]; then
    # Get the slug by splitting the name at the /
    slug=${name#*/}

    # Add the slug, type, and version to the output data
    output_data+="$(jq -n --arg slug "$slug" --arg type "$type" --arg version "$version" '{slug: $slug, type: $type, version: $version}'),"
  fi
done

# Remove the trailing comma and close the JSON array
output_data="${output_data%,}]"

# Debugging: Print the JSON data
echo "Received JSON data: $PARSED_DATA"

# Check if the JSON data is empty
if [[ -z "$PARSED_DATA" ]]; then
  echo "Error: No JSON data provided."
  exit 1
fi

# Validate JSON data
if ! echo "$PARSED_DATA" | jq empty; then
  echo "Error: Invalid JSON data."
  exit 1
fi

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

# Support for additional comment tags
sed -i.bak -e "/<!-- x-linchpin-update-readme-start -->/,/<!-- x-linchpin-update-readme-end -->/c\\<!-- x-linchpin-update-readme-start -->\n$table_output\n<!-- x-linchpin-update-readme-end -->" "$README_FILE"

# Support for plugin list
sed -i.bak -e "/<!-- x-linchpin-plugin-list-start -->/,/<!-- x-linchpin-plugin-list-end -->/c\\<!-- x-linchpin-plugin-list-start -->\n$table_output\n<!-- x-linchpin-plugin-list-end -->" "$README_FILE"

# Update the release date
current_date=$(date +"[%m/%d/%Y]")
sed -i.bak -e "/<!-- x-linchpin-release-date-start -->/,/<!-- x-linchpin-release-date-end -->/c\\<!-- x-linchpin-release-date-start -->$current_date<!-- x-linchpin-release-date-end -->" "$README_FILE"

# Remove the backup file created by sed
rm "${README_FILE}.bak"