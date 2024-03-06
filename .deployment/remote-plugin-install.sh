#!/bin/bash

# This script is used to remotely install or update plugins, themes, and packages on the hosting provider.
# Most modern hosting providers allow for interaction with the WP CLI via SSH.
#
# How it works:
# 1. We loop through the composer.lock file and check if the package is installed
# 2. If the package is installed we check if the version is different
# 3. If the version is different we update the package
# 4. If the package is not installed we install the package
#
# Since this script is running within our GitHub action we have some libraries available to us
# we are using jq to loop through our composer.lock file

install_name=$1 # install name on wpengine

# Read the composer.lock file and loop through each package
install_path="/home/wpe-user/sites/$install_name"
total_plugins=$(jq '[.packages[] | select(.type=="wordpress-plugin")] | length' ./build/composer.lock)
total_themes=$(jq '[.packages[] | select(.type=="wordpress-theme")] | length' ./build/composer.lock)

echo "::notice::Potentially Installing or Updating $total_plugins Plugins and $total_themes Themes"

# Utility method to 
ssh_wpengine_wp() {
	# Use local variables to store the function arguments
	local type=$1 # plugin or theme
	local wp_command=$2
	local slug=$3
	local version=$4

	local path="--path=$install_path"

	# Construct the full command based on whether wp_command is "is-installed" or version is blank
	local full_command
	if [[ -z $version ]]; then
		full_command="wp $type $wp_command $slug $path"
	else
		full_command="wp $type $wp_command $slug --version=$version $path"
	fi
   
    echo "Executing command: $full_command" >&2 # Debug line

	local output
	output=$(ssh -n wpengine "$full_command")
	local exit_code=$?

	if [[ $wp_command == "is-installed" ]]; then
		if [[ $exit_code == 0 ]]; then
		output="yes"
		else
		output="no"
		fi
	else
		output=$exit_code
	fi

	echo $output
}

# Get a list of installed plugins and themes
# WP Engine tunnels all SSH through a proxy which is quite slow when trying to do individual commands
# We can speed this up by running multiple commands at once and parsing the data as needed
# Originally seen on https://anchor.host/bash-hacks-to-reduce-ssh-connections-with-wp-engine/
installed_plugins_themes=$(ssh -n wpengine "wp plugin list --format=json --skip-themes --skip-plugins --skip-packages --fields=name,version; echo ""; wp theme list --format=json --skip-themes --skip-plugins --skip-packages --fields=name,version; echo ""; --path=$install_path")

IFS=$'\n' read -rd '' -a response_parsed <<<"$installed_plugins_themes"
plugin_data=${response_parsed[0]}
theme_data=${response_parsed[1]}

# Keep track of how many plugins and themes we install or update
installed_plugins=0
updated_plugins=0
skipped_plugins=0
installed_themes=0
updated_themes=0
skipped_themes=0

while read -r package; do
	# Extract the name, type, and version from the package
	name=$(echo "$package" | jq -r '.name')
	type=$(echo "$package" | jq -r '.type')
	version=$(echo "$package" | jq -r '.version')

	echo "::notice::Installing or Updating $name $type $version"

	# Check if the type is wordpress-plugin or wordpress-theme
	if [[ "$type" == "wordpress-plugin" || "$type" == "wordpress-theme" ]]; then
		# Get the slug by splitting the name at the /
		slug=${name#*/}

		# Parse the command type based on the package type in composer.lock
		theme_or_plugin=${type#wordpress-}

		if [[ $theme_or_plugin == "plugin" ]]; then

			plugin_info=$(echo $plugin_data | jq --arg slug "$slug" '.[] | select(.name == $slug)')

			if [[ -n $plugin_info ]]; then

				echo "Attempting to update plugin $slug to $version"
				current_version=$(echo $plugin_info | jq -r '.version')
				comparison_result=$(php -r "echo version_compare('$current_version', '$version');")

				if [[ "$comparison_result" == "-1" ]]; then
					updated_plugin=$(ssh_wpengine_wp "$theme_or_plugin" update "$slug" "$version")
     					if [[ updated_plugin == "0" ]]; then
	  				  ((updated_plugins++))
       					else 
	  				  echo "Could not update $slug, trying to install instead";
					  installed_theme_or_plugin=$(ssh_wpengine_wp "$theme_or_plugin" install "$slug" "$version")
					  ((installed_plugins++))
	  				fi
				else
					echo "No update required for $slug."
					((skipped_plugins++))
				fi

			else
				echo "Attempting to install $slug at version $version"
				installed_theme_or_plugin=$(ssh_wpengine_wp "$theme_or_plugin" install "$slug" "$version")
				((installed_plugins++))
			fi

		else
			theme_info=$(echo $theme_data | jq --arg slug "$slug" '.[] | select(.name == $slug)')

			if [[ -n $theme_info ]]; then
				echo "Attempting to update theme $slug to $version"

				current_version=$(echo $theme_info | jq -r '.version')
				comparison_result=$(php -r "echo version_compare('$current_version', '$version');")

				if [[ "$comparison_result" == "-1" ]]; then
					updated_theme=$(ssh_wpengine_wp "$theme_or_plugin" update "$slug" "$version")
					echo "Update theme status $updated_theme"
					((updated_themes++))
				else
					echo "No update required for $slug."
					((skipped_themes++))
				fi

			else
				echo "Attempting to install $slug at version $version"
				installed_theme_or_plugin=$(ssh_wpengine_wp "$theme_or_plugin" install "$slug" "$version")
				((installed_themes++))
			fi
		fi
	fi
done < <(jq -c '.packages[]' ./build/composer.lock)

echo "::notice::Total plugins installed: $installed_plugins"
echo "::notice::Total plugins updated: $updated_plugins"
echo "::notice::Total plugins skipped: $skipped_plugins"
echo "::notice::Total themes installed: $installed_themes"
echo "::notice::Total themes updated: $updated_themes"
echo "::notice::Total themes skipped: $skipped_themes"
