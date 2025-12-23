# mc_universal_workflow

Reusable GitHub Actions workflows + composite actions for building, testing, releasing, and runtime-testing Minecraft mods under a strict, migration-only contract.

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
      java-version: '21'
      gradle-args: build
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
      java-version: '21'
      gradle-args: test
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
    with:
      project-root: .
      java-version: '21'
      gradle-args: build
```

### Runtime test (HeadlessMC)

This uses `headlesshq/mc-runtime-test@4.1.0` under the hood and stages the built jar into `./run/mods`.

```yaml
name: Runtime Test
on:
  workflow_dispatch:

jobs:
  runtime-test:
    uses: XxInvictus/mc_universal_workflow/.github/workflows/reusable-runtime-test.yml@main
    with:
      project-root: .
      java-version: '21'
      gradle-args: build
      cache-mc: github
      fabric-api-version: none
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
- Mapping heuristics (Forge=SRG, NeoForge=Mojmap, Fabric=Intermediary).

## Optional migration helpers (out-of-band)

These scripts are provided to help migrate older/legacy `gradle.properties` key names into the canonical contract used by this repo. They are not invoked by any workflow or composite action.

- `scripts/migration/scan-legacy-gradle-properties.sh`: reports missing canonical keys and detects a small set of common aliases.
- `scripts/migration/migrate-legacy-gradle-properties.sh`: rewrites a conservative set of aliases (dry-run by default; use `--write` to update the file in place).
