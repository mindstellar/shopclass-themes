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
 * Dependency-free validator for the subset of JSON Schema this repo's own
 * schemas actually use (type/properties/required/additionalProperties/pattern/
 * const/enum/min-max length/items/uniqueItems/format:uri). Not a general
 * draft 2020-12 implementation — the two schemas in schema/ do not need one,
 * and a bare `php` binary should be able to run this with no install step.
 *
 * Usage: php tools/schema-lint.php <schema.json> <data.json> [--json]
 * Exit codes: 0 = valid, 1 = invalid, 2 = usage/read error.
 */

function fail(string $msg): void
{
    fwrite(STDERR, $msg . "\n");
    exit(2);
}

function readJson(string $path)
{
    if (!is_file($path)) {
        fail("Not a file: {$path}");
    }
    $raw = file_get_contents($path);
    if ($raw === false) {
        fail("Could not read: {$path}");
    }
    $data = json_decode($raw);
    if ($data === null && json_last_error() !== JSON_ERROR_NONE) {
        fail("Invalid JSON in {$path}: " . json_last_error_msg());
    }

    return $data;
}

/** @param array<int,string> $errors */
function validate($schema, $data, string $path, array &$errors): void
{
    if (!is_object($schema)) {
        return;
    }

    if (isset($schema->const) && $data !== $schema->const) {
        $errors[] = "{$path}: must equal " . json_encode($schema->const);
    }

    if (isset($schema->enum)) {
        $allowed = $schema->enum;
        $found = false;
        foreach ($allowed as $v) {
            if ($v === $data) {
                $found = true;
                break;
            }
        }
        if (!$found) {
            $errors[] = "{$path}: must be one of " . json_encode($allowed);
        }
    }

    if (isset($schema->type)) {
        $ok = match ($schema->type) {
            'object' => is_object($data),
            'array' => is_array($data),
            'string' => is_string($data),
            'boolean' => is_bool($data),
            'number' => is_int($data) || is_float($data),
            'integer' => is_int($data),
            default => true,
        };
        if (!$ok) {
            $errors[] = "{$path}: expected type {$schema->type}, got " . gettype($data);

            return; // further checks assume the type matched
        }
    }

    if (is_string($data)) {
        if (isset($schema->pattern) && !preg_match('#' . $schema->pattern . '#u', $data)) {
            $errors[] = "{$path}: \"{$data}\" does not match pattern /{$schema->pattern}/";
        }
        if (isset($schema->minLength) && strlen($data) < $schema->minLength) {
            $errors[] = "{$path}: shorter than minLength {$schema->minLength}";
        }
        if (isset($schema->maxLength) && strlen($data) > $schema->maxLength) {
            $errors[] = "{$path}: longer than maxLength {$schema->maxLength}";
        }
        if (
            isset($schema->format) && $schema->format === 'uri'
            && filter_var($data, FILTER_VALIDATE_URL) === false
        ) {
            $errors[] = "{$path}: \"{$data}\" is not a valid URI";
        }
    }

    if (is_array($data)) {
        if (isset($schema->minItems) && count($data) < $schema->minItems) {
            $errors[] = "{$path}: has fewer than minItems {$schema->minItems}";
        }
        if (isset($schema->maxItems) && count($data) > $schema->maxItems) {
            $errors[] = "{$path}: has more than maxItems {$schema->maxItems}";
        }
        if (!empty($schema->uniqueItems)) {
            $seen = array_map(static fn ($v) => json_encode($v), $data);
            if (count($seen) !== count(array_unique($seen))) {
                $errors[] = "{$path}: items must be unique";
            }
        }
        if (isset($schema->items)) {
            foreach ($data as $i => $item) {
                validate($schema->items, $item, "{$path}[{$i}]", $errors);
            }
        }
    }

    if (is_object($data)) {
        $props = isset($schema->properties) ? get_object_vars($schema->properties) : [];

        if (isset($schema->required)) {
            foreach ($schema->required as $req) {
                if (!property_exists($data, $req)) {
                    $errors[] = "{$path}: missing required property \"{$req}\"";
                }
            }
        }

        foreach (get_object_vars($data) as $key => $value) {
            if (isset($props[$key])) {
                validate($props[$key], $value, "{$path}.{$key}", $errors);
            } elseif (($schema->additionalProperties ?? true) === false) {
                $errors[] = "{$path}: unexpected property \"{$key}\" (additionalProperties: false)";
            }
        }
    }
}

function main(array $argv): int
{
    $args = array_slice($argv, 1);
    $json = in_array('--json', $args, true);
    $positional = array_values(array_filter($args, static fn ($a) => $a !== '--json'));

    if (count($positional) !== 2) {
        fail('Usage: php tools/schema-lint.php <schema.json> <data.json> [--json]');
    }

    [$schemaPath, $dataPath] = $positional;
    $schema = readJson($schemaPath);
    $data = readJson($dataPath);

    $errors = [];
    validate($schema, $data, '$', $errors);

    if ($json) {
        echo json_encode(['ok' => $errors === [], 'errors' => $errors], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
    } else {
        if ($errors === []) {
            echo "schema-lint: {$dataPath} is valid against {$schemaPath}\n";
        } else {
            echo "schema-lint: {$dataPath} is INVALID against {$schemaPath}\n";
            foreach ($errors as $e) {
                echo "  - {$e}\n";
            }
        }
    }

    return $errors === [] ? 0 : 1;
}

exit(main($argv));
