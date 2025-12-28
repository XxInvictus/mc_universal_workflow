#!/usr/bin/env python3
"""Resolve runtime dependencies from mod metadata.

This script is intended for CI/runtime-test workflows.

Goal:
- Read mod metadata (Fabric/Forge/Quilt).
- Extract *required* dependencies and their configured version ranges.
- Use mc-publish-style platform aliases (Modrinth/CurseForge IDs/slugs) when
  available to locate the dependency project on a publishing platform.
- Resolve each dependency to a single, concrete published artifact for the
  requested Minecraft version + loader.

It writes a temporary `dependencies.yml` compatible with this repository's
`scripts/download-runtime-deps.sh`.

Notes:
- This is best-effort for CurseForge because file listings do not expose a
  canonical "version_number" field; exact range satisfaction may not be
  enforceable in all cases.
- For Modrinth, version resolution is based on `version_number`.

Exit codes:
- 0 on success.
- Non-zero on any resolution error (missing metadata, missing aliases,
  unsatisfied ranges, network failures, etc.).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tomllib
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional, Tuple


@dataclass(frozen=True)
class Dependency:
    """A required dependency extracted from mod metadata."""

    mod_id: str
    version_range: str
    modrinth: Optional[str]
    curseforge: Optional[str]


@dataclass(frozen=True)
class ResolvedDependency:
    """A dependency pinned to a concrete artifact/version."""

    source_type: str  # modrinth|curseforge
    name: str
    modrinth_id: Optional[str] = None
    modrinth_version: Optional[str] = None
    curseforge_id: Optional[str] = None
    curseforge_file_id: Optional[str] = None


def http_get_json(url: str, user_agent: str) -> Any:
    """Fetch JSON from a URL with a User-Agent header."""

    request = urllib.request.Request(url, headers={"User-Agent": user_agent})
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read().decode("utf-8")
    return json.loads(body)


def find_first_existing(project_root: str, candidates: Iterable[str]) -> Optional[str]:
    """Return the first existing file path (relative to project_root)."""

    for rel_path in candidates:
        abs_path = os.path.join(project_root, rel_path)
        if os.path.isfile(abs_path):
            return abs_path
    return None


def parse_mc_publish_dependency_string(value: str) -> Tuple[str, Dict[str, str]]:
    """Parse an mc-publish dependency string and return (id, aliases).

    Supports a subset of mc-publish format:
      id@version(type){platform:alias}{platform2:alias2}#(ignore:github)

    We only care about:
    - id
    - platform aliases (modrinth, curseforge)
    """

    # id is everything up to the first of: @ ( { # ( )
    id_match = re.match(r"^([A-Za-z0-9_\-\.]+)", value.strip())
    if not id_match:
        raise ValueError(f"Invalid mc-publish dependency string: {value!r}")

    dep_id = id_match.group(1)
    aliases: Dict[str, str] = {}

    for platform, alias in re.findall(r"\{\s*([a-zA-Z0-9_-]+)\s*:\s*([^}]+?)\s*\}", value):
        aliases[platform.strip().lower()] = alias.strip()

    return dep_id, aliases


def extract_alias_map_from_fabric_custom(custom_obj: Any) -> Dict[str, Dict[str, str]]:
    """Extract dependency alias mappings from Fabric's custom.mc-publish.dependencies."""

    if not isinstance(custom_obj, dict):
        return {}

    mc_publish = custom_obj.get("mc-publish")
    if not isinstance(mc_publish, dict):
        return {}

    deps = mc_publish.get("dependencies")
    if not isinstance(deps, list):
        return {}

    mapping: Dict[str, Dict[str, str]] = {}
    for item in deps:
        if not isinstance(item, str):
            continue
        dep_id, aliases = parse_mc_publish_dependency_string(item)
        if aliases:
            mapping.setdefault(dep_id, {}).update(aliases)

    return mapping


def read_fabric_dependencies(project_root: str) -> List[Dependency]:
    """Read required dependencies from fabric.mod.json."""

    fabric_path = find_first_existing(
        project_root,
        [
            "src/main/resources/fabric.mod.json",
            "fabric.mod.json",
        ],
    )
    if fabric_path is None:
        return []

    with open(fabric_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    depends = data.get("depends")
    if not isinstance(depends, dict):
        depends = {}

    alias_map = extract_alias_map_from_fabric_custom(data.get("custom"))

    deps: List[Dependency] = []
    for dep_id, version_range in depends.items():
        if not isinstance(dep_id, str):
            continue
        if dep_id in {"minecraft", "java", "fabricloader"}:
            continue
        if not isinstance(version_range, str):
            version_range = "*"

        aliases = alias_map.get(dep_id, {})
        deps.append(
            Dependency(
                mod_id=dep_id,
                version_range=version_range.strip() or "*",
                modrinth=aliases.get("modrinth"),
                curseforge=aliases.get("curseforge"),
            )
        )

    return deps


def read_forge_dependencies(project_root: str) -> List[Dependency]:
    """Read required dependencies from META-INF/mods.toml."""

    mods_toml_path = find_first_existing(
        project_root,
        [
            "src/main/resources/META-INF/mods.toml",
            "META-INF/mods.toml",
            "mods.toml",
        ],
    )
    if mods_toml_path is None:
        return []

    with open(mods_toml_path, "rb") as f:
        data = tomllib.load(f)

    mods = data.get("mods")
    mod_id: Optional[str] = None
    if isinstance(mods, list) and mods and isinstance(mods[0], dict):
        mid = mods[0].get("modId")
        if isinstance(mid, str) and mid:
            mod_id = mid

    deps_root = data.get("dependencies")
    if not isinstance(deps_root, dict) or not mod_id:
        return []

    dep_entries = deps_root.get(mod_id)
    if not isinstance(dep_entries, list):
        return []

    deps: List[Dependency] = []
    for entry in dep_entries:
        if not isinstance(entry, dict):
            continue
        dep_id = entry.get("modId")
        if not isinstance(dep_id, str) or not dep_id:
            continue
        if dep_id == "minecraft":
            continue

        mandatory = entry.get("mandatory")
        if mandatory is not True:
            continue

        vr = entry.get("versionRange")
        if not isinstance(vr, str) or not vr.strip():
            vr = "*"

        mcp = entry.get("mc-publish")
        modrinth = None
        curseforge = None
        if isinstance(mcp, dict):
            ignore = mcp.get("ignore")
            if ignore is True:
                continue
            mr = mcp.get("modrinth")
            cf = mcp.get("curseforge")
            if isinstance(mr, str) and mr.strip():
                modrinth = mr.strip()
            if isinstance(cf, (str, int)):
                curseforge = str(cf).strip()

        deps.append(
            Dependency(
                mod_id=dep_id,
                version_range=vr.strip(),
                modrinth=modrinth,
                curseforge=curseforge,
            )
        )

    return deps


def read_quilt_dependencies(project_root: str) -> List[Dependency]:
    """Read required dependencies from quilt.mod.json (best-effort)."""

    quilt_path = find_first_existing(
        project_root,
        [
            "src/main/resources/quilt.mod.json",
            "quilt.mod.json",
        ],
    )
    if quilt_path is None:
        return []

    with open(quilt_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    depends = data.get("depends")
    if not isinstance(depends, list):
        depends = []

    alias_map: Dict[str, Dict[str, str]] = {}
    mcp = data.get("mc-publish")
    if isinstance(mcp, dict):
        custom_deps = mcp.get("dependencies")
        if isinstance(custom_deps, list):
            for item in custom_deps:
                if not isinstance(item, str):
                    continue
                dep_id, aliases = parse_mc_publish_dependency_string(item)
                if aliases:
                    alias_map.setdefault(dep_id, {}).update(aliases)

    deps: List[Dependency] = []
    for item in depends:
        if isinstance(item, str):
            dep_id = item
            version_range = "*"
            optional = False
        elif isinstance(item, dict):
            dep_id = item.get("id")
            if not isinstance(dep_id, str) or not dep_id:
                continue
            version_range = item.get("versions")
            if not isinstance(version_range, str) or not version_range.strip():
                version_range = "*"
            optional = item.get("optional") is True
        else:
            continue

        if optional:
            continue
        if dep_id in {"minecraft", "java"}:
            continue

        aliases = alias_map.get(dep_id, {})
        deps.append(
            Dependency(
                mod_id=dep_id,
                version_range=version_range.strip(),
                modrinth=aliases.get("modrinth"),
                curseforge=aliases.get("curseforge"),
            )
        )

    return deps


def parse_version_key(version_str: str) -> Tuple[int, ...]:
    """Parse a version into a tuple of integers for approximate ordering."""

    nums = re.findall(r"\d+", version_str)
    if not nums:
        return (0,)
    return tuple(int(n) for n in nums)


def compare_versions(a: str, b: str) -> int:
    """Compare two version strings using numeric segments."""

    ka = parse_version_key(a)
    kb = parse_version_key(b)
    if ka < kb:
        return -1
    if ka > kb:
        return 1
    return 0


@dataclass(frozen=True)
class Constraint:
    op: str
    version: str


def expand_semver_compat(op: str, version: str) -> List[Constraint]:
    """Expand ^/~ constraints into >= and < constraints."""

    key = parse_version_key(version)
    major = key[0] if len(key) > 0 else 0
    minor = key[1] if len(key) > 1 else 0

    if op == "~":
        upper = f"{major}.{minor + 1}.0"
    else:  # ^
        if major != 0:
            upper = f"{major + 1}.0.0"
        else:
            upper = f"0.{minor + 1}.0"

    return [Constraint(op=">=", version=version), Constraint(op="<", version=upper)]


def parse_constraints(range_str: str) -> List[Constraint]:
    """Parse a version range string into a list of constraints.

    Supports:
    - *
    - exact versions
    - comparisons: >=, >, <=, <, =
    - semver-ish: ^1.2.3, ~1.2.3
    - Forge/Maven interval: [1.0,2.0), (1.0,)
    """

    s = (range_str or "").strip()
    if not s or s == "*":
        return []

    # Maven interval
    if (s.startswith("[") or s.startswith("(")) and (s.endswith("]") or s.endswith(")")) and "," in s:
        left_inclusive = s.startswith("[")
        right_inclusive = s.endswith("]")
        inner = s[1:-1]
        lo, hi = [part.strip() for part in inner.split(",", 1)]
        constraints: List[Constraint] = []
        if lo:
            constraints.append(Constraint(op=">=" if left_inclusive else ">", version=lo))
        if hi:
            constraints.append(Constraint(op="<=" if right_inclusive else "<", version=hi))
        return constraints

    if s.startswith("^"):
        return expand_semver_compat("^", s[1:].strip())
    if s.startswith("~"):
        return expand_semver_compat("~", s[1:].strip())

    parts = re.split(r"\s+|\s*,\s*", s)
    constraints: List[Constraint] = []
    for part in parts:
        if not part:
            continue
        match = re.match(r"^(>=|<=|>|<|=)?\s*(.+)$", part)
        if not match:
            continue
        op = match.group(1) or "="
        version = match.group(2).strip()
        if version:
            constraints.append(Constraint(op=op, version=version))

    return constraints


def satisfies_constraints(version: str, constraints: List[Constraint]) -> bool:
    """Return True if version satisfies all constraints."""

    for c in constraints:
        cmp_val = compare_versions(version, c.version)
        if c.op == ">":
            if cmp_val <= 0:
                return False
        elif c.op == ">=":
            if cmp_val < 0:
                return False
        elif c.op == "<":
            if cmp_val >= 0:
                return False
        elif c.op == "<=":
            if cmp_val > 0:
                return False
        elif c.op == "=":
            if cmp_val != 0:
                return False
        else:
            return False

    return True


def resolve_modrinth(
    dep: Dependency,
    loader: str,
    minecraft_version: str,
    policy: str,
    user_agent: str,
) -> ResolvedDependency:
    """Resolve a dependency on Modrinth to a specific version_number."""

    assert dep.modrinth

    query = urllib.parse.urlencode(
        {
            "loaders": json.dumps([loader]),
            "game_versions": json.dumps([minecraft_version]),
        }
    )
    url = f"https://api.modrinth.com/v2/project/{urllib.parse.quote(dep.modrinth)}/version?{query}"
    versions = http_get_json(url, user_agent)

    if not isinstance(versions, list):
        raise RuntimeError(f"Unexpected Modrinth response for {dep.modrinth!r}")

    constraints = parse_constraints(dep.version_range)

    candidates: List[Dict[str, Any]] = []
    for v in versions:
        if not isinstance(v, dict):
            continue
        vn = v.get("version_number")
        if not isinstance(vn, str) or not vn:
            continue
        if constraints and not satisfies_constraints(vn, constraints):
            continue
        candidates.append(v)

    if not candidates:
        raise RuntimeError(
            f"No Modrinth versions for {dep.mod_id} ({dep.modrinth}) satisfy range '{dep.version_range}' "
            f"for loader={loader} mc={minecraft_version}"
        )

    def published_dt(item: Dict[str, Any]) -> datetime:
        value = item.get("date_published")
        if isinstance(value, str):
            try:
                return datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                return datetime.min
        return datetime.min

    candidates.sort(key=published_dt)
    chosen = candidates[0] if policy == "min" else candidates[-1]

    vn = str(chosen.get("version_number"))
    return ResolvedDependency(
        source_type="modrinth",
        name=dep.mod_id,
        modrinth_id=dep.modrinth,
        modrinth_version=vn,
    )


def curseforge_expected_loader_label(loader: str) -> str:
    """Map internal loader name to CurseForge gameVersions label."""

    return {"forge": "Forge", "neoforge": "NeoForge", "fabric": "Fabric"}[loader]


def resolve_curseforge(
    dep: Dependency,
    loader: str,
    minecraft_version: str,
    policy: str,
    user_agent: str,
) -> ResolvedDependency:
    """Resolve a dependency on CurseForge to a specific file id (best-effort)."""

    assert dep.curseforge

    # For now we require a numeric project id.
    if not re.fullmatch(r"\d+", dep.curseforge):
        raise RuntimeError(
            f"CurseForge alias for dependency {dep.mod_id} must be a numeric project id; got {dep.curseforge!r}"
        )

    mod_id = dep.curseforge
    label = curseforge_expected_loader_label(loader)

    # Try to fetch up to 200 most recent files; API is provided by api.curse.tools.
    url = f"https://api.curse.tools/v1/cf/mods/{mod_id}/files?pageSize=200"
    payload = http_get_json(url, user_agent)

    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, list):
        raise RuntimeError(f"Unexpected CurseForge response for mod id {mod_id}")

    def file_dt(item: Dict[str, Any]) -> datetime:
        value = item.get("fileDate")
        if isinstance(value, str):
            try:
                return datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                return datetime.min
        return datetime.min

    # Filter by MC version and loader label.
    filtered: List[Dict[str, Any]] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        gvs = item.get("gameVersions")
        if not isinstance(gvs, list):
            continue
        if minecraft_version not in gvs:
            continue
        if label not in gvs:
            continue
        filtered.append(item)

    if not filtered:
        raise RuntimeError(
            f"No CurseForge files for {dep.mod_id} ({mod_id}) match loader={label} mc={minecraft_version}"
        )

    # Best-effort range enforcement: if the range is an exact numeric version,
    # require it to appear in the fileName/displayName.
    exact = dep.version_range.strip()
    constraints = parse_constraints(exact)
    if constraints and all(c.op == "=" for c in constraints) and len(constraints) == 1:
        needle = constraints[0].version
        narrowed: List[Dict[str, Any]] = []
        for item in filtered:
            fn = str(item.get("fileName") or "")
            dn = str(item.get("displayName") or "")
            if needle in fn or needle in dn:
                narrowed.append(item)
        if narrowed:
            filtered = narrowed
        else:
            raise RuntimeError(
                f"CurseForge dependency {dep.mod_id} has exact range '{dep.version_range}' but no fileName/displayName contains it"
            )

    filtered.sort(key=file_dt)
    chosen = filtered[0] if policy == "min" else filtered[-1]

    file_id = chosen.get("id")
    if not isinstance(file_id, int):
        raise RuntimeError(f"CurseForge file entry missing numeric id for {mod_id}")

    return ResolvedDependency(
        source_type="curseforge",
        name=dep.mod_id,
        curseforge_id=mod_id,
        curseforge_file_id=str(file_id),
    )


def write_dependencies_yml(out_path: str, resolved: List[ResolvedDependency]) -> None:
    """Write a minimal dependencies.yml with resolved runtime entries."""

    lines: List[str] = []
    lines.append('version: "1.0"')
    lines.append("settings:")
    lines.append("  auto_resolve_latest: false")
    lines.append("")
    lines.append("dependencies:")
    lines.append("  runtime:")

    if not resolved:
        lines.append("    []")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        return

    for dep in resolved:
        lines.append(f"    - name: {dep.name}")
        if dep.source_type == "modrinth":
            assert dep.modrinth_id and dep.modrinth_version
            lines.append("      identifiers:")
            lines.append(f"        modrinth_id: {dep.modrinth_id}")
            lines.append("      version:")
            lines.append(f"        default: {json.dumps(dep.modrinth_version)}")
            lines.append("      source:")
            lines.append("        type: modrinth")
        elif dep.source_type == "curseforge":
            assert dep.curseforge_id and dep.curseforge_file_id
            lines.append("      identifiers:")
            lines.append(f"        curseforge_id: {dep.curseforge_id}")
            lines.append(f"        curseforge_file_id: {dep.curseforge_file_id}")
            lines.append("      source:")
            lines.append("        type: curseforge")
        else:
            raise RuntimeError(f"Unsupported resolved source type: {dep.source_type}")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main() -> int:
    """CLI entrypoint."""

    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--loader", required=True, choices=["forge", "neoforge", "fabric"])
    parser.add_argument("--minecraft-version", required=True)
    parser.add_argument("--policy", required=True, choices=["min", "max"])
    parser.add_argument("--out", required=True, help="Path (relative to project root) to write dependencies.yml")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail if any required dependency lacks Modrinth/CurseForge alias mapping",
    )
    parser.add_argument("--user-agent", default="XxInvictus/mc_universal_workflow")

    args = parser.parse_args()

    project_root = args.project_root
    out_rel = args.out
    out_abs = os.path.join(project_root, out_rel)

    deps = []
    deps.extend(read_fabric_dependencies(project_root))
    deps.extend(read_forge_dependencies(project_root))
    deps.extend(read_quilt_dependencies(project_root))

    # De-duplicate by mod_id; prefer entries that include platform aliases.
    by_id: Dict[str, Dependency] = {}
    for dep in deps:
        existing = by_id.get(dep.mod_id)
        if existing is None:
            by_id[dep.mod_id] = dep
            continue
        score_existing = int(existing.modrinth is not None) + int(existing.curseforge is not None)
        score_new = int(dep.modrinth is not None) + int(dep.curseforge is not None)
        if score_new > score_existing:
            by_id[dep.mod_id] = dep

    required_deps = list(by_id.values())

    resolved: List[ResolvedDependency] = []
    for dep in sorted(required_deps, key=lambda d: d.mod_id):
        if dep.modrinth:
            resolved.append(
                resolve_modrinth(dep, args.loader, args.minecraft_version, args.policy, args.user_agent)
            )
        elif dep.curseforge:
            resolved.append(
                resolve_curseforge(dep, args.loader, args.minecraft_version, args.policy, args.user_agent)
            )
        else:
            if args.strict:
                raise RuntimeError(
                    f"Required dependency '{dep.mod_id}' has no mc-publish Modrinth/CurseForge alias in metadata"
                )

    os.makedirs(os.path.dirname(out_abs) or ".", exist_ok=True)
    write_dependencies_yml(out_abs, resolved)

    print(f"generated_deps_file={out_rel}")
    print(f"generated_deps_count={len(resolved)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
