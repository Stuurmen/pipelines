# Pipelines

Reusable GitHub Actions workflows that build a project and deploy it to a staging and a production server over SSH.

| Workflow | Status |
| --- | --- |
| `deploy-v2.2.0.yml` | Current. Use this for new projects. |
| `deploy-v2.1.1.yml` (tag `v2.1.1`) | Same as v2.2.0 without the PHP checks. Move to v2.2.0 (see [Moving from v2.1.x](#moving-from-v21x)). |
| `deploy-v2.1.0.yml` (tag `v2.1.0`) | Works for Yarn 1 and npm projects, fails on Yarn 4 projects. |
| `deploy-v2.0.0.yml` | Older projects. Move them to v2.2.0 (see [Migrating from v2.0.0](#migrating-from-v200)). |
| `deploy-v1.0.0.yml`, `deploy-unprocessed-v1.0.0.yml` | Legacy. No project uses them. |

## Deploy v2.2.0

On every push to the staging or production branch, the workflow:

1. Reads `pipeline.json` and fails the run if it is missing or invalid, or if the branch belongs to neither environment. A green run always means something was deployed.
2. Installs the Node dependencies with yarn or npm, runs `build:production` when the project has it (otherwise `build`), then `npm test`.
3. Lints every PHP file with `php -l`, then runs PHPCS with the project's own config (`phpcs.xml`, `phpcs.xml.dist`, `.phpcs.xml` or `ruleset.xml`). Errors fail the run; warnings are reported but don't.
4. Runs `composer install --no-dev` when `source.composer` is on.
5. Copies the files into a clean release, leaving out what a server should never serve: every top-level dotfile except `.htaccess` (so `.git/`, `.github/`, `.cache-loader/` and editor and linter config), `node_modules/`, `pipeline.json`, `.env` files, Markdown files, `phpcs.xml`, and the package and Composer manifests and lockfiles.
6. Uploads the release with rsync over SSH.

Only one deploy per environment runs at a time, and each one shows up under Environments in the project's repository.

### Set up a project

**1. SSH key.** Generate a key pair for deploying. Add the public key to `~/.ssh/authorized_keys` of the user on the server, and store the private key as a GitHub secret named `DEPLOYMENT_SSH_PRIVATE_KEY`. That can be an organization secret limited to the repositories that need it, or a repository secret.

**2. Workflow.** Add `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [ master, dev ]
  workflow_dispatch:

jobs:
  deploy:
    uses: Stuurmen/pipelines/.github/workflows/deploy-v2.2.0.yml@v2.2.0
    secrets:
      ssh_private_key: ${{ secrets.DEPLOYMENT_SSH_PRIVATE_KEY }}
```

The branches must match the ones in `pipeline.json`.

**3. Config.** Add `pipeline.json` to the root of the project:

```json
{
  "production": {
    "branch": "master",
    "host": "203.0.113.10",
    "port": "22",
    "username": "deploy",
    "path": "./public/wp-content/themes/example",
    "node_version": "20",
    "url": "https://www.example.com"
  },
  "staging": {
    "branch": "dev",
    "host": "203.0.113.20",
    "port": "22",
    "username": "deploy",
    "path": "./public/wp-content/themes/example",
    "node_version": "20",
    "url": "https://staging.example.stuurmen.nl"
  },
  "source": {
    "path": "",
    "package_manager": "yarn"
  }
}
```

### pipeline.json reference

Per environment (`production`, `staging`):

| Key | Required | Meaning |
| --- | --- | --- |
| `branch` | yes | Branch that deploys to this environment. |
| `host`, `port`, `username` | yes | SSH login on the server. |
| `path` | yes | Folder on the server to deploy into, relative to the user's home folder. Letters, digits and `. _ / ~ -` only. |
| `node_version` | when there is a `package.json` | Node.js version for the build. |
| `url` | no | Site address, shown on the deployment in GitHub. |

Under `source`:

| Key | Default | Meaning |
| --- | --- | --- |
| `path` | `""` (the whole repository) | Folder to deploy, for example `dist/`. |
| `package_manager` | `""` (no install) | `yarn` or `npm`. Yarn 2 and later only work when the project pins its version with `yarn set version` (`yarnPath` in `.yarnrc.yml`); otherwise the runner's Yarn 1 can't read the lockfile. |
| `composer` | `false` | Run `composer install --no-dev` and deploy `vendor/`. When off, `vendor/` on the server is never touched. Composer 2.2 and later refuse a lockfile without an `allow-plugins` section, which older projects often lack: add `config.allow-plugins` to `composer.json` and run `composer update --lock` before you turn this on. |
| `php_version` | `8.3` | PHP version for PHP lint, PHPCS and Composer. Required when `composer` is on. Use a version every package in `composer.lock` accepts. |
| `phpcs` | `true` | Run PHPCS. The pipeline brings PHPCS 3.13.6 and uses the project's config; a config without `<file>` entries scans the whole project. Set to `false` only for a project that doesn't pass yet. |
| `delete` | `false` | Remove files on the server that are no longer in the release. Refused when `path` points at a shared folder such as `themes` or `public_html`. |
| `exclude` | `[]` | Extra rsync patterns to leave out of the release, for example `["/resources/assets/"]`. |

### Build check without deploying

Pass `dry_run: true` to build and assemble the release without connecting to a server, for example on pull requests. The release is uploaded as an artifact named `release-<environment>`, so you can check what would be deployed.

```yaml
jobs:
  build:
    uses: Stuurmen/pipelines/.github/workflows/deploy-v2.2.0.yml@v2.2.0
    with:
      dry_run: true
```

### Moving from v2.1.x

1. Point `uses:` at `deploy-v2.2.0.yml@v2.2.0`.
2. PHPCS is on by default, and projects that were never checked usually fail it. Run `phpcbf` with the project's config to fix layout errors, exclude rules the code can't follow in its `phpcs.xml`, and check the result on staging. Until the project passes, set `"phpcs": false` in `pipeline.json`.

### Migrating from v2.0.0

1. Point `uses:` at `deploy-v2.2.0.yml@v2.2.0`. `pipeline.json` needs no changes, but PHPCS is on by default: see step 2 of [Moving from v2.1.x](#moving-from-v21x).
2. Check what changes for the project:
   - Projects with a `build:production` script now ship that build instead of the development build.
   - `pipeline.json`, `README.md`, `package.json` and the other files listed above are no longer copied, and the first deploy removes the `pipeline.json` that v2.0.0 left on the server.
   - Leave `composer` and `delete` off unless you want them. Without them, files that are already on the server stay there, and `vendor/` is never touched.

## Testing

`test/run.sh` runs the real workflow with [act](https://github.com/nektos/act) against a throwaway SSH server in Docker. It covers a staging deploy with Composer, a production deploy with `delete`, a dry run, Yarn 1 and Yarn 4 projects, PHPCS switched off and a `ruleset.xml` without file list, and the cases that must fail: an unknown branch, invalid JSON, a PHP syntax error, a PHPCS error, a missing PHPCS config, an unsafe path, and `delete` on a shared folder.

```bash
brew install act
test/run.sh
```

Run a single scenario with `test/run.sh unsafe_path`. The script swaps `upload-artifact` for v4 because act's artifact server doesn't support newer versions; everything else runs as published. On Apple silicon, projects that use node-sass need `--container-architecture linux/amd64`, because node-sass has no arm64 Linux build.

Design decisions are recorded in [docs/adr](docs/adr).
