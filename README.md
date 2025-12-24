# mc_universal_workflow

Reusable GitHub Actions workflows + composite actions for building, testing, releasing, and runtime-testing Minecraft mods under a strict, migration-only contract.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)  

| CI | 1.20.X | 1.21.X |
| :---: | :---: | :---: |
| [![CI Test](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/ci.yml) | - | - |
| - | [![Forge](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-forge.yml/badge.svg?branch=1.20.1-forge)](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-forge.yml) | [![Forge](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-forge.yml/badge.svg?branch=1.21.1-forge)](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-forge.yml) |
| - | [![Fabric](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-fabric.yml/badge.svg?branch=1.20.1-fabric)](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-fabric.yml) | [![Fabric](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-fabric.yml/badge.svg?branch=1.21.1-fabric)](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-fabric.yml) |
| - | - | [![NeoForge](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-neoforge.yml/badge.svg?branch=1.21.1-neoforge)](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-neoforge.yml) |
| - | [![Multiloader](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-multiloader.yml/badge.svg?branch=1.20.1-multiloader)](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-multiloader.yml) | [![Multiloader](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-multiloader.yml/badge.svg?branch=1.21.1-multiloader)](https://github.com/XxInvictus/mc_universal_workflow/actions/workflows/build-test-multiloader.yml) |

## Contract (non-negotiable)

- Branch-per-version: one Minecraft version per branch (no in-branch MC version matrix).
- Migration-only: canonical `gradle.properties` keys are required; missing keys fail fast.
- Structure-authoritative: loader classification is derived from repo layout (and enforced against declared properties).
- Groovy Gradle only (this repo assumes `build.gradle`, not Kotlin DSL).

## Required `gradle.properties`

Always required:

```properties
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
loader_multi=false
java_version=21
```

Single-loader branches:

```properties
loader_type=forge
```

Multi-loader branches:

```properties
loader_multi=true
active_loaders=forge,fabric
```

Supported loaders: `forge`, `neoforge`, `fabric`.

## Artifact naming (enforced)

See [build_docs/ARTIFACT_NAMING_CONTRACT.md](build_docs/ARTIFACT_NAMING_CONTRACT.md).

## Reusable workflows

All workflows are meant to be called from a consumer repo via `workflow_call`.

All reusable workflows accept a `runs-on` input so you can select your runner label (for example `ubuntu-latest` or `self-hosted`).

### Build

`.github/workflows/build.yml` in the consumer repo:

```yaml
name: Build
on:
  push:
  pull_request:

jobs:
  build:
    uses: XxInvictus/mc_universal_workflow/.github/workflows/reusable-build.yml@main
    with:
      project-root: .
      gradle-args: build
      runs-on: ubuntu-latest

      # Optional (same-run artifact handoff): upload jars for later jobs.
      upload-artifacts: false
      artifact-name: build-artifacts
```

### Test

```yaml
name: Test
on:
  push:
  pull_request:

jobs:
  test:
    uses: XxInvictus/mc_universal_workflow/.github/workflows/reusable-test.yml@main
    with:
      project-root: .
      gradle-args: test
      runs-on: ubuntu-latest
```

### Release (build + upload artifacts)

```yaml
name: Release
on:
  push:
    branches:
      - '*-release'

jobs:
  release:
    uses: XxInvictus/mc_universal_workflow/.github/workflows/reusable-release.yml@main
    secrets: inherit
    with:
      project-root: .
      gradle-args: build
      runs-on: ubuntu-latest

      # Optional publishing (via Kir-Antipov/mc-publish)
      publish-github: true
      publish-modrinth: false
      modrinth-id: ${{ vars.MODRINTH_PROJECT_ID }}
      publish-curseforge: false
      curseforge-id: ${{ vars.CURSEFORGE_PROJECT_ID }}
```

If publishing is enabled, the workflow creates a tag named:

```text
${minecraft_version}-${mod_version}
```

Publishing secrets (in the consumer repo):

- `MODRINTH_TOKEN` (required if `publish-modrinth: true`)
- `CURSEFORGE_TOKEN` (required if `publish-curseforge: true`)

Recommended repository variables (in the consumer repo):

- `MODRINTH_PROJECT_ID` (used by `modrinth-id`)
- `CURSEFORGE_PROJECT_ID` (used by `curseforge-id`)

### Runtime test (HeadlessMC)

This uses `headlesshq/mc-runtime-test@4.1.0` under the hood and stages the built jar into `./run/mods`.

> [!WARNING]
> Runtime tests are intended for self-hosted runners. They can take several minutes and download/cache large Minecraft assets; running them on GitHub-hosted runners may incur unexpected costs.

```yaml
name: Runtime Test
on:
  workflow_dispatch:

jobs:
  runtime-test:
    uses: XxInvictus/mc_universal_workflow/.github/workflows/reusable-runtime-test.yml@main
    with:
      project-root: .
      gradle-args: build
      cache-mc: github
      runs-on: self-hosted

      # Optional (same-run artifact handoff): download jars and skip Gradle build.
      use-build-artifacts: false
      artifact-name: build-artifacts

Notes:

- Reusable build/test/release/runtime-test workflows enable Gradle caching via `gradle/actions/setup-gradle@v4`.
- Artifact handoff is only meant for jobs within the same workflow run (build uploads -> runtime-test downloads).
```

## Optional `dependencies.yml`

`dependencies.yml` is optional enrichment-only:

- Local builds must not depend on it.
- Runtime tests may use it to download published dependency mods into `./run/mods` (no secrets; public APIs only).

This repo rejects any “latest”/auto-resolve-latest configuration for determinism.

Schema and examples: [build_docs/DEPENDENCIES_YML_SCHEMA.md](build_docs/DEPENDENCIES_YML_SCHEMA.md)

## Utilities

- Migration (incremental): [build_docs/MIGRATION_GUIDE.md](build_docs/MIGRATION_GUIDE.md)
- Consumer adoption: [build_docs/CONSUMER_ADOPTION.md](build_docs/CONSUMER_ADOPTION.md)
- Property schema and rules: [build_docs/GRADLE_PROPERTIES_SCHEMA.md](build_docs/GRADLE_PROPERTIES_SCHEMA.md)
- Extract properties: [build_docs/EXTRACT_PROPERTIES.md](build_docs/EXTRACT_PROPERTIES.md)
- One-shot validation: [build_docs/HEALTH_CHECK.md](build_docs/HEALTH_CHECK.md)
- Troubleshooting: [build_docs/TROUBLESHOOTING.md](build_docs/TROUBLESHOOTING.md)

Templates:

- [templates/consumer-workflows](templates/consumer-workflows)
- [templates/consumer-workflows/build-test-runtime-test.yml](templates/consumer-workflows/build-test-runtime-test.yml)
- [templates/gradle.properties.single.properties](templates/gradle.properties.single.properties)
- [templates/gradle.properties.multi.properties](templates/gradle.properties.multi.properties)
- [templates/dependencies.yml](templates/dependencies.yml)

Notes:

- Modrinth downloads are pinned by exact `version.default` matching Modrinth `version_number`.
- CurseForge downloads are pinned by `identifiers.curseforge_file_id` (required) and validated against loader + Minecraft version.

## What this repo validates

- Canonical property presence + loader gating (migration-only).
- Enforced artifact paths.
- Artifact sanity (valid jar + required loader metadata file).
- Mapping heuristics (Forge=SRG or Mojmap, NeoForge=Mojmap, Fabric=Intermediary).

## Optional migration helpers (out-of-band)

These scripts are provided to help migrate older/legacy `gradle.properties` key names into the canonical contract used by this repo. They are not invoked by any workflow or composite action.

- `scripts/migration/scan-legacy-gradle-properties.sh`: reports missing canonical keys and detects a small set of common aliases.
- `scripts/migration/migrate-legacy-gradle-properties.sh`: rewrites a conservative set of aliases (dry-run by default; use `--write` to update the file in place).
