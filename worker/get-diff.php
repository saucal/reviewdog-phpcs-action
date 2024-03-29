<?php
require __DIR__ . '/vendor/autoload.php';

use ptlis\DiffParser\Parser;
use ptlis\DiffParser\Line;
$parser     = new Parser();
$patch_data = file_get_contents( '/worker/curr-diff.diff' );
$changeset  = $parser->parse( $patch_data, Parser::VCS_GIT );
$files      = $changeset->getFiles();

$changed = array();

foreach ( $files as $file ) {
	$filename = $file->getNewFilename();
	if ( '/dev/null' === $filename ) {
		continue;
	}

	$filename = getcwd() . '/' . $filename;

	$changed[ $filename ] = array();
	$hunk_list            = $file->getHunks();
	foreach ( $hunk_list as $hunk ) {
		$lines = $hunk->getLines();
		foreach ( $lines as $line ) {
			$line_num = $line->getNewLineNo();
			if ( $line_num < 0 ) {
				continue;
			}

			if ( $line->getOperation() === Line::UNCHANGED ) {
				continue;
			}

			$changed[ $filename ][ $line_num ] = true;
		}
	}
}
