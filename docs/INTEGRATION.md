# Integration Guide (Consumer Repos)

This guide shows how to adopt the reusable GitHub Actions workflows in this repo from a consumer mod repository.

## What you get

- Reusable workflows for build, test, release, and runtime testing.
- Strict, deterministic validation (fail fast when the contract is not met).

## Prerequisites

- GitHub-hosted Ubuntu runners (the workflows assume common Linux tools are available).
- Groovy Gradle (`build.gradle`).
- You accept the repo contract:
  - Canonical `gradle.properties` keys are required.
  - One Minecraft version per branch (no in-branch MC matrix).
  - Deterministic artifact naming (no custom patterns).
  - No “latest” dependency resolution behavior.

## 1) Add canonical `gradle.properties`

Your repo must contain a `gradle.properties` at the project root.

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

## 2) Ensure repo layout matches loader intent

Loader detection is structure-authoritative:

- Single-loader: no loader module directories are required.
- Multi-loader: create module directories with `build.gradle`, for example:
  - `forge/build.gradle`
  - `fabric/build.gradle`

If structure indicates multi-loader (2+ loader module directories) but `loader_multi` is not `true`, validation fails.

## 3) Ensure your build produces the enforced jar name(s)

Artifact naming is enforced and derived only from `gradle.properties`.

Single-loader:

```text
build/libs/${mod_id}-${loader_type}-${minecraft_version}-${mod_version}.jar
```

Multi-loader:

```text
${loader}/build/libs/${mod_id}-${loader}-${minecraft_version}-${mod_version}.jar
```

If your build produces a different name or path, workflows will fail.

## 4) Add the consumer workflows

Copy one or more templates from [templates/consumer-workflows](../templates/consumer-workflows) into your consumer repo under `.github/workflows/`.

Templates:

- `build.yml`
- `test.yml`
- `release.yml`
- `runtime-test.yml`

Then update the `uses:` reference to point to the exact ref you want (branch, tag, or commit SHA).

## 5) Runtime tests (HeadlessMC)

The runtime-test workflow uses `headlesshq/mc-runtime-test@4.1.0` and expects mods staged into:

- `./run/mods`

This repo’s prep logic stages:

- Your built mod jar
- Optional additional mods
- Optional downloaded runtime deps from `dependencies.yml`

## 6) Optional `dependencies.yml` (runtime-only dependency downloads)

`dependencies.yml` is optional enrichment-only:

- Local builds must not depend on it.
- Runtime tests may use it to download published dependency mod jars into `./run/mods`.

Determinism rules:

- No `settings.auto_resolve_latest: true`
- No `version.latest: true`
- No `version.default: latest`
- Pinned versions only

Use the starter template: [templates/dependencies.yml](../templates/dependencies.yml)

Supported sources (no secrets required):

- Modrinth (pinned by exact `version.default` matching Modrinth `version_number`)
- CurseForge (pinned by `identifiers.curseforge_file_id`, required)
- Direct URL (including `file://` for offline tests)

## 7) Recommended local validation (optional)

If you have bash and common CLI tools installed locally, you can validate before pushing:

```bash
bash scripts/health-check.sh --project-root .
```

## Troubleshooting

### “Missing required property '…'”

- Add the canonical keys to `gradle.properties`.

### “Structure indicates multi-loader (…) but loader_multi is not true”

- If you have multiple loader module directories (for example `forge/` and `fabric/` with `build.gradle`), set:
  - `loader_multi=true`
  - `active_loaders=...`

### “expected artifact missing” / “artifact does not exist”

- Ensure your Gradle build produces the jar exactly at the enforced path.

### unzip errors

- The produced jar must be a valid, non-empty zip.

### “mapping mismatch”

- This repo uses heuristic detection:
  - Forge expects SRG
  - NeoForge expects Mojmap
  - Fabric expects Intermediary

### Missing tools locally (jq/yq/zip/unzip/strings)

- CI installs required tools.
- Locally, install them or expect some optional scripts/tests to skip.
