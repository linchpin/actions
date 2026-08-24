#!/usr/bin/env node
/**
 * Report which entries in a package.json "overrides" block no longer do
 * anything, so pins added to dodge an advisory get cleaned up once upstream
 * catches up instead of accumulating forever.
 *
 * For each override, in a scratch copy of the manifest + lockfile:
 *   remove that ONE override -> re-resolve -> compare against the pin.
 *
 *   STILL NEEDED  removing it would drop the package below the pinned version
 *   REDUNDANT     it already resolves at or above the pin without the override
 *   DANGLING      the package is no longer in the dependency tree at all
 *
 * Two flags are load-bearing:
 *   --package-lock-only  resolve the graph without downloading node_modules
 *   --ignore-scripts     the scratch copy has no node_modules, so a `prepare`
 *                        hook (husky is the common one) would fail the install
 *                        and mask every result as an error
 *
 * The project itself is never mutated.
 *
 * Usage: node check-overrides.mjs <dir> [<dir> ...]
 * Env:   GITHUB_STEP_SUMMARY  markdown report is appended when set
 *        OVERRIDES_JSON_OUT   machine-readable results written here when set
 */

import { execFileSync } from 'node:child_process';
import {
	mkdtempSync,
	cpSync,
	existsSync,
	readFileSync,
	writeFileSync,
	appendFileSync,
	rmSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dirs = process.argv.slice( 2 );

if ( ! dirs.length ) {
	console.error( 'usage: check-overrides.mjs <dir> [<dir> ...]' );
	process.exit( 2 );
}

/** Strip an npm override key like `ajv@8` down to the bare package name. */
const bareName = ( key ) => {
	const at = key.lastIndexOf( '@' );
	return at > 0 ? key.slice( 0, at ) : key;
};

/**
 * Numeric semver compare, prerelease-insensitive. Overrides are pinned to
 * exact release versions by convention, so major.minor.patch is enough and
 * avoids taking on a semver dependency inside a composite action.
 */
const isBelow = ( version, pin ) => {
	const parts = ( v ) => String( v ).replace( /^[^\d]*/, '' ).split( '-' )[ 0 ].split( '.' ).map( Number );
	const [ a, b ] = [ parts( version ), parts( pin ) ];
	for ( let i = 0; i < 3; i++ ) {
		const [ x, y ] = [ a[ i ] || 0, b[ i ] || 0 ];
		if ( x !== y ) return x < y;
	}
	return false;
};

/** Every resolved version of `name` in a lockfile, with its tree position. */
const resolvedVersions = ( lockPath, name ) => {
	const lock = JSON.parse( readFileSync( lockPath, 'utf8' ) );
	const suffix = `node_modules/${ name }`;
	return Object.entries( lock.packages ?? {} )
		.filter( ( [ path ] ) => path === suffix || path.endsWith( `/${ suffix }` ) )
		.map( ( [ path, meta ] ) => ( { path, version: meta.version } ) )
		.filter( ( entry ) => entry.version );
};

const uniq = ( values ) => [ ...new Set( values ) ].join( ', ' );

/** Probe every override in one project. */
const checkProject = ( dir ) => {
	const manifestPath = join( dir, 'package.json' );
	const lockPath = join( dir, 'package-lock.json' );

	if ( ! existsSync( manifestPath ) ) {
		return { dir, skipped: 'no package.json', overrides: [] };
	}
	if ( ! existsSync( lockPath ) ) {
		return { dir, skipped: 'no package-lock.json', overrides: [] };
	}

	const manifest = JSON.parse( readFileSync( manifestPath, 'utf8' ) );
	const overrides = manifest.overrides ?? {};
	const keys = Object.keys( overrides );

	if ( ! keys.length ) {
		return { dir, skipped: 'no overrides block', overrides: [] };
	}

	const work = mkdtempSync( join( tmpdir(), 'check-overrides-' ) );
	const results = [];

	try {
		for ( const key of keys ) {
			const name = bareName( key );
			const pin = overrides[ key ];

			// Fresh manifest + lockfile per probe, with this one override gone.
			const probe = JSON.parse( readFileSync( manifestPath, 'utf8' ) );
			delete probe.overrides[ key ];
			writeFileSync( join( work, 'package.json' ), JSON.stringify( probe, null, 2 ) );
			cpSync( lockPath, join( work, 'package-lock.json' ) );

			let status;
			let detail;

			try {
				execFileSync(
					'npm',
					[
						'install',
						'--package-lock-only',
						'--ignore-scripts',
						'--no-audit',
						'--no-fund',
					],
					{
						cwd: work,
						encoding: 'utf8',
						stdio: [ 'ignore', 'pipe', 'pipe' ],
						maxBuffer: 64 * 1024 * 1024,
					}
				);

				const found = resolvedVersions( join( work, 'package-lock.json' ), name );
				const below = found.filter( ( entry ) => isBelow( entry.version, pin ) );

				if ( ! found.length ) {
					status = 'DANGLING';
					detail = 'not in the dependency tree at all';
				} else if ( ! below.length ) {
					status = 'REDUNDANT';
					detail = `already resolves to ${ uniq(
						found.map( ( e ) => e.version )
					) } without the override`;
				} else {
					status = 'STILL NEEDED';
					detail = `would drop to ${ uniq(
						below.map( ( e ) => e.version )
					) } at ${ below.length } tree position(s)`;
				}
			} catch ( error ) {
				status = 'ERROR';
				detail = String( error.stderr || error.message || error )
					.split( '\n' )
					.filter( ( line ) => line && ! line.startsWith( 'npm warn' ) )
					.slice( 0, 2 )
					.join( ' ' )
					.slice( 0, 300 );
			}

			results.push( { key, name, pin, status, detail } );
			console.log( `${ dir }  ${ status.padEnd( 13 ) } ${ key.padEnd( 24 ) } ${ detail }` );
		}
	} finally {
		rmSync( work, { recursive: true, force: true } );
	}

	return { dir, overrides: results };
};

const projects = dirs.map( checkProject );

const all = projects.flatMap( ( p ) => p.overrides );
const counts = {
	redundant: all.filter( ( o ) => o.status === 'REDUNDANT' ).length,
	dangling: all.filter( ( o ) => o.status === 'DANGLING' ).length,
	needed: all.filter( ( o ) => o.status === 'STILL NEEDED' ).length,
	errored: all.filter( ( o ) => o.status === 'ERROR' ).length,
};

// ---------------------------------------------------------------- reporting

const ICON = {
	REDUNDANT: '🟡',
	DANGLING: '⚪',
	'STILL NEEDED': '🟢',
	ERROR: '🔴',
};

const lines = [ '## npm overrides staleness', '' ];

if ( counts.redundant || counts.dangling ) {
	lines.push(
		`**${ counts.redundant + counts.dangling } override(s) look removable** ` +
			`— ${ counts.redundant } redundant, ${ counts.dangling } dangling. ` +
			`${ counts.needed } still doing work.`,
		'',
		'> A redundant override is not automatically safe to delete: one added to hold a',
		'> security floor still guards against a future downgrade. Treat this as a prompt',
		'> to review, not an instruction to remove.',
		''
	);
} else if ( ! all.length ) {
	lines.push( 'No `overrides` block found in any of the projects checked.', '' );
} else {
	lines.push( `All ${ counts.needed } override(s) are still doing work. Nothing to clean up.`, '' );
}

for ( const project of projects ) {
	lines.push( `### \`${ project.dir }\`` );
	if ( project.skipped ) {
		lines.push( '', `_Skipped — ${ project.skipped }._`, '' );
		continue;
	}
	lines.push( '', '| | Override | Pinned | Finding |', '| --- | --- | --- | --- |' );
	for ( const o of project.overrides ) {
		lines.push( `| ${ ICON[ o.status ] } | \`${ o.key }\` | \`${ o.pin }\` | ${ o.status } — ${ o.detail } |` );
	}
	lines.push( '' );
}

const report = lines.join( '\n' );
console.log( `\n${ report }` );

if ( process.env.GITHUB_STEP_SUMMARY ) {
	appendFileSync( process.env.GITHUB_STEP_SUMMARY, `${ report }\n` );
}

if ( process.env.OVERRIDES_JSON_OUT ) {
	writeFileSync(
		process.env.OVERRIDES_JSON_OUT,
		JSON.stringify( { counts, projects }, null, 2 )
	);
}

if ( process.env.GITHUB_OUTPUT ) {
	appendFileSync(
		process.env.GITHUB_OUTPUT,
		[
			`redundant-count=${ counts.redundant }`,
			`dangling-count=${ counts.dangling }`,
			`needed-count=${ counts.needed }`,
			`removable-count=${ counts.redundant + counts.dangling }`,
			'',
		].join( '\n' )
	);
}

// Annotate so findings surface without opening the summary.
for ( const project of projects ) {
	for ( const o of project.overrides ) {
		if ( o.status === 'REDUNDANT' || o.status === 'DANGLING' ) {
			console.log(
				`::notice title=Removable override::${ project.dir }: ${ o.key } (${ o.status.toLowerCase() }) — ${ o.detail }`
			);
		}
		if ( o.status === 'ERROR' ) {
			console.log(
				`::warning title=Override probe failed::${ project.dir }: ${ o.key } — ${ o.detail }`
			);
		}
	}
}

if ( counts.errored && process.env.FAIL_ON_ERROR === 'true' ) {
	console.error( `\n${ counts.errored } override probe(s) failed.` );
	process.exit( 1 );
}

if ( ( counts.redundant || counts.dangling ) && process.env.FAIL_ON_REDUNDANT === 'true' ) {
	console.error( `\n${ counts.redundant + counts.dangling } override(s) look removable.` );
	process.exit( 1 );
}
