#!/usr/bin/env node
//
// Add to the open release-please PR every commit it ships that its notes leave
// out, under the section release-please would have put it in.
//
// release-please collects a release's commits by walking the target branch's
// history newest first, by commit date, and stops at the previous release's
// commit. A branch that lived beside it and arrives by a merge commit brings
// commits older than that release, and the walk stops before it reaches them.
// That is exactly a rolling `maintenance` snapshot: linchpin.com's
// snapshot/2026-10-26 (#1925) carried twenty Renovate updates into main, and
// the 0.81.7 release PR (#1924) listed none of them, only the few commits dated
// after 0.81.6. The snapshot PR is merged with a merge commit precisely so each
// update keeps its changelog line, and that only holds if something lists them.
//
// release-please builds the GitHub release from the merged release PR's body,
// so completing the body completes the release, and everything that reads it:
// the deployment log's notes and summary, and the changelog Mantle shows on
// each environment.
//
// What counts as shipped is git's answer, not the walk's: every commit that is
// not a merge in <previous release tag>..origin/<target>. Each one whose first
// line is a conventional commit of a type the config shows, and whose sha the
// body does not already link, is added as release-please writes an entry:
//
//   * **scope:** subject ([#123](…/issues/123)) ([abc1234](…/commit/<sha>))
//
// Each section it adds to is re-sorted by scope and then subject, the order
// release-please writes, and a section the body lacks is added in the config's
// order. Nothing else in the body changes, and a body already complete is left
// alone, so it is safe to run after every release-please run. release-please
// rewrites the body whenever it differs from what it would write, which is
// every run once this has added something, so it runs after each of them.
//
// Merge commits are skipped: what they bring is listed commit by commit, and a
// merge into the target is always newer than the previous release, so the walk
// already has its title. Only the notes change. A missed `feat` or breaking
// commit should also have raised the version; that is reported, not fixed.
//
// Only a single-package manifest (one path, ".") is handled; any other config
// is reported and left alone.
//
// Run it from a checkout of the target branch with full history and tags:
//
//   DRY_RUN=true GITHUB_REPOSITORY=owner/repo node complete-release-notes.mjs
//
// prints the body it would write and changes nothing.
//
// Env: GITHUB_REPOSITORY (required), GH_TOKEN (for gh), TARGET_BRANCH (default
// main), PULL_REQUEST (the release PR's number; found by its branch when
// empty), CONFIG_FILE (default release-please-config.json), MANIFEST_FILE
// (default .release-please-manifest.json), DRY_RUN, GITHUB_SERVER_URL,
// GITHUB_STEP_SUMMARY and GITHUB_OUTPUT. Outputs: added (how many entries),
// pull-request (the release PR's number, when there is one).

import { execFileSync } from 'node:child_process';
import { appendFileSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const REPOSITORY = process.env.GITHUB_REPOSITORY || '';
const TARGET = process.env.TARGET_BRANCH || 'main';
const CONFIG_FILE = process.env.CONFIG_FILE || 'release-please-config.json';
const MANIFEST_FILE = process.env.MANIFEST_FILE || '.release-please-manifest.json';
const DRY_RUN = process.env.DRY_RUN === 'true';
const HOST = process.env.GITHUB_SERVER_URL || 'https://github.com';
const SUMMARY = process.env.GITHUB_STEP_SUMMARY || '';
const OUTPUT = process.env.GITHUB_OUTPUT || '';

// release-please's sections when the config names none.
const DEFAULT_SECTIONS = [
	{ type: 'feat', section: 'Features' },
	{ type: 'feature', section: 'Features' },
	{ type: 'fix', section: 'Bug Fixes' },
	{ type: 'perf', section: 'Performance Improvements' },
	{ type: 'revert', section: 'Reverts' },
	{ type: 'docs', section: 'Documentation', hidden: true },
	{ type: 'style', section: 'Styles', hidden: true },
	{ type: 'chore', section: 'Miscellaneous Chores', hidden: true },
	{ type: 'refactor', section: 'Code Refactoring', hidden: true },
	{ type: 'test', section: 'Tests', hidden: true },
	{ type: 'build', section: 'Build System', hidden: true },
	{ type: 'ci', section: 'Continuous Integration', hidden: true },
];

const HEADER = /^(?<type>[\w-]+)(?:\((?<scope>[^()\r\n]+)\))?(?<bang>!)?: (?<subject>.+)$/;
const BULLET = /^\* (?:\*\*(?<scope>.+?):\*\* )?(?<rest>.*)$/;
const DELIMITER = '---';

function run( command, args, options = {} ) {
	return execFileSync( command, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, ...options } );
}

function quietly( command, args ) {
	try {
		return run( command, args, { stdio: [ 'ignore', 'pipe', 'ignore' ] } ).trim();
	} catch {
		return '';
	}
}

function output( name, value ) {
	if ( OUTPUT ) {
		appendFileSync( OUTPUT, `${ name }=${ value }\n` );
	}
}

function summary( text ) {
	if ( SUMMARY ) {
		appendFileSync( SUMMARY, `${ text }\n` );
	}
}

function done( message, added = 0, pull = '' ) {
	console.log( message );
	summary( message );
	output( 'added', added );
	output( 'pull-request', pull );
	process.exit( 0 );
}

// The open release PR into the target: the one named, or the one on
// release-please's branch for it.
function releasePullRequest() {
	if ( process.env.PULL_REQUEST ) {
		return JSON.parse( run( 'gh', [ 'api', `repos/${ REPOSITORY }/pulls/${ process.env.PULL_REQUEST }` ] ) );
	}

	const open = JSON.parse(
		run( 'gh', [ 'api', '--paginate', '--slurp', `repos/${ REPOSITORY }/pulls?state=open&base=${ TARGET }&per_page=100` ] )
	).flat();

	return (
		open.find(
			( pull ) =>
				pull.head.ref.startsWith( `release-please--branches--${ TARGET }` ) &&
				pull.labels.some( ( label ) => 'autorelease: pending' === label.name )
		) || null
	);
}

// The previous release's tag, as release-please names it, else the plainer
// names it might have been cut under.
function previousTag( config, manifest ) {
	const pkg = config.packages?.[ '.' ] || {};
	const version = manifest[ '.' ];
	const component = pkg.component ?? pkg[ 'package-name' ] ?? '';
	const withV = pkg[ 'include-v-in-tag' ] ?? config[ 'include-v-in-tag' ] ?? true;
	const withComponent = pkg[ 'include-component-in-tag' ] ?? config[ 'include-component-in-tag' ] ?? true;
	const separator = pkg[ 'tag-separator' ] ?? config[ 'tag-separator' ] ?? '-';
	const named = `${ withComponent && component ? component + separator : '' }${ withV ? 'v' : '' }${ version }`;

	for ( const tag of new Set( [ named, `v${ version }`, version ] ) ) {
		if ( quietly( 'git', [ 'rev-parse', '-q', '--verify', `refs/tags/${ tag }^{commit}` ] ) ) {
			return tag;
		}
	}

	return '';
}

// type => section, for the types the notes show, and the sections in order.
function sectionsOf( config ) {
	const listed = config.packages?.[ '.' ]?.[ 'changelog-sections' ] || config[ 'changelog-sections' ] || DEFAULT_SECTIONS;
	const byType = new Map();
	const order = [];

	for ( const { type, section, hidden } of listed ) {
		if ( ! hidden && ! byType.has( type ) ) {
			byType.set( type, section );
		}

		if ( ! hidden && ! order.includes( section.trimEnd() ) ) {
			order.push( section.trimEnd() );
		}
	}

	return { byType, order };
}

// release-please's escaping of a subject: angle brackets outside backticks.
function escape( subject ) {
	return subject.replace( /``[^`].*[^`]``|`[^`]*`|<|>/g, ( match ) => {
		if ( match.length > 1 ) {
			return match;
		}

		return '<' === match ? '&lt;' : '&gt;';
	} );
}

function entry( commit ) {
	const base = `${ HOST }/${ REPOSITORY }`;
	const subject = escape( commit.subject ).replace( /#(\d+)/g, `[#$1](${ base }/issues/$1)` );
	const scope = commit.scope ? `**${ commit.scope }:** ` : '';

	return `* ${ scope }${ subject } ([${ commit.sha.slice( 0, 7 ) }](${ base }/commit/${ commit.sha }))`;
}

function sortKey( line ) {
	const match = line.match( BULLET );

	return [ match?.groups.scope || '', match?.groups.rest || line ];
}

function byScopeThenSubject( a, b ) {
	const [ scopeA, restA ] = sortKey( a );
	const [ scopeB, restB ] = sortKey( b );

	if ( scopeA !== scopeB ) {
		return scopeA < scopeB ? -1 : 1;
	}

	if ( restA === restB ) {
		return 0;
	}

	return restA < restB ? -1 : 1;
}

// Every commit in the range that is not a merge, with its conventional header.
function shipped( tag ) {
	const log = run( 'git', [ 'log', '--no-merges', '--format=%H%x1f%B%x1e', `${ tag }..origin/${ TARGET }` ] );
	const commits = [];

	for ( const record of log.split( '\x1e' ) ) {
		const [ sha, message = '' ] = record.replace( /^\n+/, '' ).split( '\x1f' );
		const header = message.split( '\n' )[ 0 ].trim();
		const match = header.match( HEADER );

		if ( sha && match ) {
			commits.push( { sha, ...match.groups } );
		}
	}

	return commits;
}

// A commit every file of which is under an excluded path is not the package's.
function excluded( sha, paths ) {
	if ( ! paths.length ) {
		return false;
	}

	const files = quietly( 'git', [ 'diff-tree', '--no-commit-id', '--name-only', '-r', sha ] ).split( '\n' ).filter( Boolean );

	return files.length > 0 && files.every( ( file ) => paths.some( ( path ) => file === path || file.startsWith( `${ path.replace( /\/$/, '' ) }/` ) ) );
}

// The body with each section's new entries added. Only the lines between
// release-please's first and last `---` are its notes, as it parses them.
function complete( body, additions, order ) {
	const lines = body.replace( /\r\n/g, '\n' ).split( '\n' );
	const first = lines.indexOf( DELIMITER );
	let last = lines.lastIndexOf( DELIMITER );

	if ( -1 === first ) {
		return null;
	}

	if ( last === first ) {
		last = lines.length;
	}

	const notes = lines.slice( first + 1, last );
	const headings = () =>
		notes.flatMap( ( line, index ) => ( line.startsWith( '### ' ) ? [ { index, title: line.slice( 4 ).trimEnd() } ] : [] ) );

	for ( const title of order ) {
		const entries = additions.get( title );

		if ( ! entries?.length ) {
			continue;
		}

		const all = headings();
		const at = all.findIndex( ( heading ) => heading.title === title );

		if ( -1 !== at ) {
			const end = at + 1 < all.length ? all[ at + 1 ].index : notes.length;
			const bullets = [];

			for ( let index = all[ at ].index + 1; index < end; index++ ) {
				if ( notes[ index ].startsWith( '* ' ) ) {
					bullets.push( index );
				}
			}

			if ( ! bullets.length ) {
				notes.splice( all[ at ].index + 1, 0, '', ...entries.sort( byScopeThenSubject ) );
				continue;
			}

			const from = bullets[ 0 ];
			const to = bullets[ bullets.length - 1 ];

			// One bullet a line, as release-please writes them, can be re-sorted
			// as a whole; anything else keeps its order and gains the new ones.
			if ( to - from + 1 === bullets.length ) {
				const merged = [ ...notes.slice( from, to + 1 ), ...entries ].sort( byScopeThenSubject );
				notes.splice( from, to - from + 1, ...merged );
			} else {
				notes.splice( to + 1, 0, ...entries.sort( byScopeThenSubject ) );
			}

			continue;
		}

		// A new section goes before the first one that comes after it.
		const rank = order.indexOf( title );
		const next = all.find( ( heading ) => order.includes( heading.title ) && order.indexOf( heading.title ) > rank );
		const block = [ `### ${ title }`, '', ...entries.sort( byScopeThenSubject ) ];

		if ( next ) {
			notes.splice( next.index, 0, ...block, '', '' );
			continue;
		}

		// Else after the notes' last line of text.
		let tail = notes.length - 1;

		while ( tail >= 0 && '' === notes[ tail ].trim() ) {
			tail--;
		}

		notes.splice( tail + 1, 0, '', '', ...block );
	}

	return [ ...lines.slice( 0, first + 1 ), ...notes, ...lines.slice( last ) ].join( '\n' );
}

if ( ! REPOSITORY ) {
	console.error( 'Set GITHUB_REPOSITORY to owner/name.' );
	process.exit( 1 );
}

const config = JSON.parse( readFileSync( CONFIG_FILE, 'utf8' ) );
const manifest = JSON.parse( readFileSync( MANIFEST_FILE, 'utf8' ) );

if ( 1 !== Object.keys( manifest ).length || ! ( '.' in manifest ) ) {
	done( `${ MANIFEST_FILE } lists more than the root package; only a single-package manifest is completed, so the notes are left as release-please wrote them.` );
}

const pull = releasePullRequest();

if ( ! pull ) {
	done( `No release PR is open into \`${ TARGET }\`; nothing to complete.` );
}

const tag = previousTag( config, manifest );

if ( ! tag ) {
	done( `No tag for the previous release, ${ manifest[ '.' ] }, is in this checkout (it needs full history and tags), so #${ pull.number }'s notes are left alone.`, 0, pull.number );
}

const { byType, order } = sectionsOf( config );
const listed = new Set( [ ...( pull.body || '' ).matchAll( /\/commit\/([0-9a-f]{40})/g ) ].map( ( match ) => match[ 1 ] ) );
const excludes = config.packages?.[ '.' ]?.[ 'exclude-paths' ] || [];
const missing = shipped( tag ).filter(
	( commit ) => byType.has( commit.type ) && ! listed.has( commit.sha ) && ! excluded( commit.sha, excludes )
);

if ( ! missing.length ) {
	done( `#${ pull.number } already lists every commit in ${ tag }..${ TARGET } its sections show.`, 0, pull.number );
}

const additions = new Map();

for ( const commit of missing.reverse() ) {
	const section = byType.get( commit.type ).trimEnd();
	additions.set( section, [ ...( additions.get( section ) || [] ), entry( commit ) ] );
}

const body = complete( pull.body || '', additions, order );

if ( null === body ) {
	done( `#${ pull.number }'s body is not one release-please wrote (no \`---\` line), so it is left alone.`, 0, pull.number );
}

const report = [
	`### Release notes completed: #${ pull.number }`,
	'',
	`release-please's walk missed ${ missing.length } of the commits in \`${ tag }..${ TARGET }\`. Added:`,
	'',
	...[ ...additions ].flatMap( ( [ section, entries ] ) => [ `**${ section }**`, '', ...entries, '' ] ),
];

if ( missing.some( ( commit ) => 'feat' === commit.type || 'feature' === commit.type || commit.bang ) ) {
	report.push( '> [!WARNING]', '> A missed commit is a feature or a breaking change, so the version release-please chose may be too low.', '' );
}

if ( DRY_RUN ) {
	console.log( body );
	summary( report.join( '\n' ) );
	output( 'added', missing.length );
	output( 'pull-request', pull.number );
	process.exit( 0 );
}

const file = join( mkdtempSync( join( tmpdir(), 'release-notes-' ) ), 'body.md' );
writeFileSync( file, body );
run( 'gh', [ 'pr', 'edit', String( pull.number ), '--repo', REPOSITORY, '--body-file', file ] );

console.log( report.join( '\n' ) );
summary( report.join( '\n' ) );
output( 'added', missing.length );
output( 'pull-request', pull.number );
