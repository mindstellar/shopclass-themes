<?php

/*
 * This file is part of Shopclass Themes (Mindstellar).
 * Copyright (c) 2026 Mindstellar Community
 *
 * Distributed under the GNU General Public License v3.0 or later. See LICENSE.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/**
 * Prints the value of one header field from a plugin/theme index.php, using
 * the exact "first match anywhere in the file" rule PACKAGE-SPEC §3.1
 * documents and tools/package-lint.php implements — so a Version comparison
 * done from this script agrees with what core would actually parse.
 *
 * Usage: php tools/read-header-field.php <field-label> <index.php>
 * Prints the trimmed value and exits 0, or prints nothing and exits 1 if the
 * field is not present.
 */

if ($argc !== 3) {
    fwrite(STDERR, "Usage: php tools/read-header-field.php <field-label> <index.php>\n");
    exit(2);
}

[, $label, $file] = $argv;

$contents = @file_get_contents($file);
if ($contents === false) {
    fwrite(STDERR, "Could not read: {$file}\n");
    exit(2);
}

if (preg_match('|' . preg_quote($label, '|') . ':([^\r\t\n]*)|i', $contents, $m)) {
    echo trim($m[1]) . "\n";
    exit(0);
}

exit(1);
