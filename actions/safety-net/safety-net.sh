#!/bin/bash

# Install Safety Net on a development server as an mu-plugin, load every site
# once so it scrubs the production data the last sync copied there, and fail
# unless every site reports it done.
#
# Runs ON THE GITHUB RUNNER — every server call goes over SSH.
#
# Nothing here passes --skip-plugins to WP-CLI. Safety Net runs as WordPress
# loads, before plugins_loaded, while WP-CLI's --skip-plugins still hides the
# active plugins list from get_option(): a first run under it finds nothing to
# deactivate and marks the step done anyway.
#
# Expects (all via the environment, set by action.yml): SSH_ALIAS, WP_PATH, ZIP

# SC2016: the PHP strings hold PHP variables, for PHP to expand.
# SC2029: every ssh command line is built on the runner on purpose.
# shellcheck disable=SC2016,SC2029

set -uo pipefail

SSH_ALIAS="${SSH_ALIAS:-safetynet}"
WP_PATH="${WP_PATH:?WP_PATH is required}"
ZIP="${ZIP:?ZIP is required}"
MU="wp-content/mu-plugins"

# Run a command in the WordPress root. WP_PATH is left unquoted on the server
# so that WP Engine's and Cloudways' ~-relative paths expand there.
remote() {
	ssh -n "$SSH_ALIAS" "cd $WP_PATH || exit 9; $1"
}

# The PHP below goes inside single quotes on the server, so it holds none.
ENV_PHP='echo "SAFETY_NET_ENV=" . wp_get_environment_type() . PHP_EOL;'
SITES_PHP='echo "SAFETY_NET_SITES=" . wp_json_encode( is_multisite() ? array_values( array_map( static function ( $site ) { return $site->domain . $site->path; }, get_sites( array( "number" => 0, "archived" => 0, "deleted" => 0, "spam" => 0 ) ) ) ) : array( "" ) ) . PHP_EOL;'
STATUS_PHP='echo "SAFETY_NET_STATUS=" . wp_json_encode( rest_do_request( "/safety-net/v1/status" )->get_data() ) . PHP_EOL;'

# A site is done when Safety Net is loaded there and every step it runs on its
# own has run: the same flags /wp-json/safety-net/v1/status reports.
DONE='.active == true and .environment == "development" and .options_scrubbed == true and .plugins_deactivated == true and .data_deleted == true and .transients_deleted == true and .emails_enabled == false'
WHY_NOT='[
	(if .active != true then "Safety Net is not loaded" else empty end),
	(if .active == true and .environment != "development" then "its environment is \(.environment)" else empty end),
	(if .active == true and .options_scrubbed != true then "options not scrubbed" else empty end),
	(if .active == true and .plugins_deactivated != true then "plugins not deactivated" else empty end),
	(if .active == true and .data_deleted != true then (if .data_kept == true then "SAFETY_NET_DELETE_DATA keeps its users and orders" else "users and orders not deleted" end) else empty end),
	(if .active == true and .transients_deleted != true then "transients not deleted" else empty end),
	(if .emails_enabled == true then "Send emails is switched on" else empty end)
] | join(", ")'

marker() { grep -m1 "^$1=" | cut -d= -f2-; }

# --- the server's own word on what it is -------------------------------------

echo "➤ Asking the server for its environment type"
env_out=$(remote "wp eval '$ENV_PHP' 2>&1")
if [ $? -eq 9 ]; then
	echo "::error::Could not enter $WP_PATH on the server"
	exit 1
fi
env_type=$(marker SAFETY_NET_ENV <<<"$env_out")
if [ "$env_type" != "development" ]; then
	echo "::error::The server says its environment type is '${env_type:-unknown}', not development, so Safety Net was not installed."
	[ -n "$env_type" ] || tail -n 5 <<<"$env_out"
	exit 1
fi
echo "  development"

# --- install ------------------------------------------------------------------

echo "➤ Installing Safety Net in $MU/safety-net"
if ! ssh "$SSH_ALIAS" "cd $WP_PATH && mkdir -p $MU && cat > $MU/.safety-net-incoming.zip" <"$ZIP"; then
	echo "::error::Could not upload safety-net.zip"
	exit 1
fi

# Unpacked beside the live copy and swapped in with two renames.
if ! remote "set -e; cd $MU; rm -rf .safety-net-incoming .safety-net-previous; mkdir .safety-net-incoming; unzip -q .safety-net-incoming.zip -d .safety-net-incoming; test -f .safety-net-incoming/safety-net/safety-net.php; if [ -e safety-net ] || [ -L safety-net ]; then mv safety-net .safety-net-previous; fi; mv .safety-net-incoming/safety-net safety-net; rm -rf .safety-net-incoming .safety-net-incoming.zip .safety-net-previous"; then
	echo "::error::Could not unpack Safety Net into $MU/safety-net"
	exit 1
fi

# The loader is what makes Safety Net active: mu-plugins load on every request
# whatever the active plugins list says, and the nightly sync replaces that list
# with production's. It loads Safety Net only on a development site, and a
# missing safety-net/ is a fatal error rather than a site left unprotected.
if ! ssh "$SSH_ALIAS" "cd $WP_PATH && cat > $MU/.safety-net-loader.tmp && mv $MU/.safety-net-loader.tmp $MU/safety-net-loader.php" <<'PHP'; then
<?php
/**
 * Plugin Name: Safety Net (development only)
 * Description: Loads Safety Net from mu-plugins/safety-net while this site's environment type is development, and never otherwise. Installed by linchpin/actions (Deploy's safety_net input).
 */

if ( 'development' === wp_get_environment_type() ) {
	require_once WPMU_PLUGIN_DIR . '/safety-net/safety-net.php';
}
PHP
	echo "::error::Could not write $MU/safety-net-loader.php"
	exit 1
fi

# --- load every site, and check it ---------------------------------------------

echo "➤ Loading every site"
sites_out=$(remote "wp eval '$SITES_PHP' 2>&1")
sites_json=$(marker SAFETY_NET_SITES <<<"$sites_out")
if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$sites_json"; then
	echo "::error::Could not list the sites on the server."
	tail -n 5 <<<"$sites_out"
	exit 1
fi

summary="| Site | Safety Net |"$'\n'"| --- | --- |"$'\n'
failed=0
while IFS= read -r url; do
	label="${url:-$WP_PATH}"
	url_arg=""
	[ -z "$url" ] || url_arg="--url='$url'"
	why="no status"
	# Each load runs whatever is still undone, so a slow site gets three.
	for attempt in 1 2 3; do
		out=$(remote "wp $url_arg eval '$STATUS_PHP' 2>&1")
		status=$(marker SAFETY_NET_STATUS <<<"$out")
		if jq -e "$DONE" >/dev/null 2>&1 <<<"$status"; then
			why=""
			break
		fi
		if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$status"; then
			why=$(jq -r "$WHY_NOT" <<<"$status")
		else
			why="no status: $(tail -n 1 <<<"$out")"
		fi
		echo "  $label: $why (load $attempt of 3)"
	done
	if [ -z "$why" ]; then
		echo "  ✓ $label"
		summary+="| $label | Scrubbed, emails blocked |"$'\n'
	else
		echo "::error::$label: $why"
		summary+="| $label | ❌ $why |"$'\n'
		failed=$((failed + 1))
	fi
done < <(jq -r '.[]' <<<"$sites_json")

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	printf '### Safety Net\n\n%s' "$summary" >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$failed" -gt 0 ]; then
	echo "::error::Safety Net has not finished on $failed site(s), so nothing was deployed."
	exit 1
fi
