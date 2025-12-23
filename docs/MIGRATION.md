# Migration Guide (Existing Repos)

This repo is migration-only: workflows and scripts expect a canonical `gradle.properties` and will fail fast if required keys are missing.

## 0) Decide your branch strategy

This repo assumes branch-per-version:

- One Minecraft version per branch.
- No in-branch Minecraft version matrix.

If you currently build multiple Minecraft versions from one branch, split those branches first.

## 1) Make `gradle.properties` canonical

Add required keys to `gradle.properties` at the repo root.

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

## 2) Optional: use the out-of-band migration helpers

These helpers are intentionally not invoked by any workflow or action.

- `scripts/migration/scan-legacy-gradle-properties.sh`
- `scripts/migration/migrate-legacy-gradle-properties.sh`

Example:

```bash
# Report missing canonical keys + detected aliases
bash scripts/migration/scan-legacy-gradle-properties.sh --file gradle.properties

# Dry-run rewrite to stdout
bash scripts/migration/migrate-legacy-gradle-properties.sh --file gradle.properties

# Write back in-place (creates a backup)
bash scripts/migration/migrate-legacy-gradle-properties.sh --file gradle.properties --write
```

## 3) Align repo layout with loader intent

Loader detection is structure-authoritative:

- If you have loader module directories with `build.gradle` (for example `forge/` + `fabric/`), set `loader_multi=true` and list them in `active_loaders`.
- If you are single-loader, ensure `loader_multi=false` and set `loader_type`.

## 4) Fix artifact naming to match the contract

Your build must produce jars at deterministic paths.

Single-loader:

```text
build/libs/${mod_id}-${minecraft_version}-${mod_version}.jar
```

Multi-loader:

```text
${loader}/build/libs/${mod_id}-${loader}-${minecraft_version}-${mod_version}.jar
```

## 5) Adopt the consumer workflows

Follow the steps in [INTEGRATION.md](INTEGRATION.md) to copy templates into `.github/workflows/` and point `uses:` at the correct ref.

## 6) Validate locally (optional)

If you have bash + common CLI tools installed locally:

```bash
bash scripts/validate-gradle-properties.sh --project-root .
bash scripts/quick-detect.sh --project-root .
bash scripts/health-check.sh --project-root .
```
