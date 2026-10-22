# 2. Run PHPCS from the pipeline, with each project's own config

Date: 2026-10-22

## Context

The deploy pipeline has to check PHP syntax and coding standards before it deploys. A project that lists PHP_CodeSniffer as a Composer dev dependency can pin an old version: PHPCS 2.x doesn't run on PHP 8. Installing it from the project also needs all its dev dependencies, which older lockfiles can't always install on current Composer.

## Decision

The pipeline installs PHPCS 3.13.6 itself through setup-php and runs it with the project's own config (`phpcs.xml`, `phpcs.xml.dist`, `.phpcs.xml` or `ruleset.xml`). A config without `<file>` entries scans the whole project, skipping `vendor/` and `node_modules/`. Errors fail the run, warnings don't. PHPCS is on by default; `source.phpcs: false` turns it off for a project that doesn't pass yet. Every PHP file outside `vendor/` and `node_modules/`, except Blade templates, also goes through `php -l` on the project's PHP version (8.3 by default).

## Consequences

- PHPCS works the same on every project, whatever its lockfile says.
- PHPCS 3 reads the same configs as 2.x, so a project keeps its existing `phpcs.xml`.
- Moving a project to v2.2.0 can mean fixing PHPCS errors first, or switching PHPCS off explicitly.
- Upgrading PHPCS is a change here, in one place.
