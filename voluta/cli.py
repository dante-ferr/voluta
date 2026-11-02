#!/usr/bin/env python3
"""Resolve Voluta settings without modifying core defaults or application state."""
import argparse
import copy
import fcntl
import json
import math
import os
from pathlib import Path
import re
import socket
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FEATURES = {
    "dolphin": "Custom styling and live palette hook (takes effect on next launch)",
    "session_restore": "Window restore on login and background session saving",
}


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "voluta"


def hostname(value=None):
    name = value if value is not None else socket.gethostname()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name) or name in (".", ".."):
        raise ValueError("invalid hostname")
    return name


def validate_value(value):
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError("non-finite numbers are not supported")
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str) or not key:
                raise ValueError("configuration keys must be nonempty strings")
            validate_value(item)
    elif isinstance(value, list):
        for item in value:
            validate_value(item)


def read(path):
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict) or type(data.get("version")) is not int or data["version"] != 1:
        raise ValueError(f"{path}: expected settings version 1")
    unknown = set(data) - {"version", "features", "hyprland"}
    if unknown:
        raise ValueError(f"{path}: unknown sections: {', '.join(sorted(unknown))}")
    for section in ("features", "hyprland"):
        if not isinstance(data.get(section, {}), dict):
            raise ValueError(f"{path}: {section} must be an object")
    for key, value in data.get("features", {}).items():
        if key not in FEATURES or type(value) is not bool:
            raise ValueError(f"{path}: unsupported feature or non-boolean selection: {key}")
    validate_value(data)
    return data


def merge(base, override):
    result = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge(result[key], value)
        else:
            # Arrays and scalars replace as a unit. False is an explicit override.
            result[key] = copy.deepcopy(value)
    return result


def resolve(directory, host):
    shared = directory / "settings.json"
    per_host = directory / "hosts" / f"{hostname(host)}.json"
    result = read(ROOT / "voluta/defaults.json")
    result = merge(result, read(shared))
    result = merge(result, read(per_host))
    return result, shared.exists() or per_host.exists()


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         delete=False) as handle:
            temporary = Path(handle.name)
            json.dump(data, handle, indent=2, ensure_ascii=False, allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        # Preserve a companion-managed settings-file symlink rather than replacing it.
        destination = path.resolve() if path.is_symlink() else path
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def lua(value):
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        # Decimal byte escapes avoid Lua/JSON differences and code injection.
        return '"' + ''.join(f'\\{byte:03d}' for byte in value.encode("utf-8")) + '"'
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return "{" + ",".join(f"[{lua(key)}]={lua(item)}" for key, item in value.items()) + "}"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", type=Path, default=config_home())
    parser.add_argument("--host", default=socket.gethostname())
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="create empty overrides; never overwrite settings")
    init.add_argument("--preserve-session", action="store_true", help="retain legacy session restoration")
    commands.add_parser("show", help="show resolved settings")
    commands.add_parser("render-lua", help=argparse.SUPPRESS)
    check = commands.add_parser("enabled", help="exit 0 if a feature is enabled, 1 if disabled")
    check.add_argument("name", choices=FEATURES)
    check.add_argument("--legacy", action="store_true", help=argparse.SUPPRESS)
    feature = commands.add_parser("feature", help="list or change feature selections")
    feature.add_argument("action", choices=("list", "enable", "disable", "reset"))
    feature.add_argument("name", nargs="?", choices=FEATURES)
    feature.add_argument("--scope", choices=("shared", "host"), default="shared")
    config = commands.add_parser("config", help="set/reset a Hyprland setting override")
    config.add_argument("action", choices=("set", "reset"))
    config.add_argument("key", help="dotted key, e.g. input.kb_layout")
    config.add_argument("value", nargs="?", help="JSON value; quote strings as JSON")
    config.add_argument("--scope", choices=("shared", "host"), default="shared")
    companion = commands.add_parser("companion", help="attach a local companion settings directory")
    companion.add_argument("action", choices=("attach",))
    companion.add_argument("path", type=Path)
    args = parser.parse_args(argv)
    directory = args.config_dir.expanduser().absolute()
    host = hostname(args.host)
    if args.command == "companion":
        source = args.path.expanduser().resolve(strict=True)
        if source == directory or not (source / "settings.json").is_file():
            raise ValueError("companion must be a different directory containing settings.json")
        read(source / "settings.json")
        for path in (source / "hosts").glob("*.json"):
            hostname(path.stem)
            read(path)
        if directory.is_symlink() and directory.resolve() == source:
            print("Companion already attached")
            return 0
        if directory.exists() or directory.is_symlink():
            raise ValueError("settings destination exists; back it up or merge it before attaching")
        if directory in source.parents:
            raise ValueError("companion cannot be inside the settings destination")
        directory.parent.mkdir(parents=True, exist_ok=True)
        directory.symlink_to(source, target_is_directory=True)
        print(f"Companion attached: {directory} -> {source}")
        return 0
    if args.command in ("init", "config") or (args.command == "feature" and args.action != "list"):
        # Serialize writers without placing runtime lock files in a companion repo.
        import hashlib
        lock_dir = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "voluta"
        lock_dir.mkdir(parents=True, exist_ok=True)
        lock_name = hashlib.sha256(str(directory.resolve()).encode()).hexdigest() + ".lock"
        with (lock_dir / lock_name).open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            # Validate the effective configuration before mutating any override.
            _, initialized = resolve(directory, host)
            if args.command != "init" and not initialized:
                raise ValueError("initialize settings first: voluta init (use --preserve-session for the existing setup)")
            path = directory / "settings.json"
            if args.command == "init":
                if path.exists() or path.is_symlink():
                    print("Settings already exist; preserved")
                    return 0
                data = {"version": 1, "features": {}, "hyprland": {}}
                if args.preserve_session:
                    data["features"]["session_restore"] = True
                atomic_write(path, data)
                print(f"Initialized {path}")
                return 0
            if args.scope == "host":
                path = directory / "hosts" / f"{host}.json"
            data = read(path) or {"version": 1}
            if args.command == "feature":
                if not args.name:
                    raise ValueError("feature name is required")
                node = data.setdefault("features", {})
                if args.action == "reset":
                    node.pop(args.name, None)
                else:
                    node[args.name] = args.action == "enable"
            else:
                if args.action == "set" and args.value is None:
                    raise ValueError("set requires a JSON value")
                keys = args.key.split(".")
                if len(keys) < 2 or not all(re.fullmatch(r"[A-Za-z0-9_:-]+", key) for key in keys):
                    raise ValueError("use a dotted Hyprland section.key")
                node = data.setdefault("hyprland", {})
                for key in keys[:-1]:
                    node = node.setdefault(key, {})
                    if not isinstance(node, dict):
                        raise ValueError("key traverses a scalar override; reset its parent first")
                if args.action == "reset":
                    node.pop(keys[-1], None)
                else:
                    value = json.loads(args.value)
                    validate_value(value)
                    if value is None:
                        raise ValueError("use reset instead of null")
                    node[keys[-1]] = value
            atomic_write(path, data)
        effective, _ = resolve(directory, host)
        if args.command == "feature":
            print(f"{args.name}: effective={str(effective['features'][args.name]).lower()} ({args.scope} override updated)")
            print("Session changes are picked up by the login supervisor; Dolphin changes apply on next launch.")
        else:
            print("Override saved; reload Hyprland to apply it")
        return 0
    settings, initialized = resolve(directory, host)
    if args.command == "show":
        print(json.dumps({"initialized": initialized, "host": host, **settings}, indent=2, ensure_ascii=False))
    elif args.command == "render-lua":
        print("return " + lua({"initialized": initialized, **settings}))
    elif args.command == "enabled":
        # Before explicit initialization, existing installs retain their startup behavior.
        value = settings["features"][args.name] if initialized or not args.legacy else True
        return 0 if value else 1
    else:
        for name, description in FEATURES.items():
            print(f"{name}: {'enabled' if settings['features'][name] else 'disabled'} — {description}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, TypeError, RecursionError) as error:
        print(f"voluta: {error}", file=sys.stderr)
        raise SystemExit(2)
