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
    "rgb": "Wallust lighting for explicitly selected compatible peripherals",
    "browser": "Browser-specific palette integration",
    "developer_shell": "Personal developer shell hooks",
    "obs": "OBS recording keybindings",
    "sddm": "System-wide Voluta login theme (explicit privileged setup)",
    "rice_switch": "Switch between Voluta and another local rice",
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


def validate_appearance(appearance):
    background = appearance.get("background", {})
    if not isinstance(background, dict) or set(background) - {"source", "darken"}:
        raise ValueError("appearance.background accepts source and darken")
    if "source" in background and background["source"] not in ("background", *(f"color{i}" for i in range(16))):
        raise ValueError("background source must be background or color0..color15")
    amount = background.get("darken", 0.35)
    if type(amount) not in (int, float) or not math.isfinite(amount) or not 0 <= amount <= 1:
        raise ValueError("background darken must be a number between 0 and 1")


def read(path):
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict) or type(data.get("version")) is not int or data["version"] != 1:
        raise ValueError(f"{path}: expected settings version 1")
    unknown = set(data) - {"version", "features", "hyprland", "environment", "apps", "paths", "keybindings", "startup", "monitors", "workspaces", "waybar_output", "dolphin_rhi", "rgb", "appearance"}
    if unknown:
        raise ValueError(f"{path}: unknown sections: {', '.join(sorted(unknown))}")
    for section in ("features", "hyprland", "environment", "apps", "paths", "keybindings", "startup", "rgb", "appearance"):
        if not isinstance(data.get(section, {}), dict):
            raise ValueError(f"{path}: {section} must be an object")
    for key, value in data.get("features", {}).items():
        if key not in FEATURES or type(value) is not bool:
            raise ValueError(f"{path}: unsupported feature or non-boolean selection: {key}")
    for key, value in data.get("environment", {}).items():
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) or (value is not None and not isinstance(value, str)):
            raise ValueError(f"{path}: invalid environment entry")
        if key == "GBM_BACKEND" and value is not None or key == "LIBVA_DRIVER_NAME" and value == "nvidia" or key == "NVD_BACKEND" and value == "direct":
            raise ValueError(f"{path}: unsafe GPU environment override: {key}")
    for section in ("keybindings", "startup"):
        if any(not isinstance(v, str) and v is not False for v in data.get(section, {}).values()):
            raise ValueError(f"{path}: {section} values must be commands or false")
    for section in ("monitors", "workspaces"):
        if section in data and not isinstance(data[section], list):
            raise ValueError(f"{path}: {section} must be a list")
    if "dolphin_rhi" in data and type(data["dolphin_rhi"]) is not bool:
        raise ValueError(f"{path}: dolphin_rhi must be boolean")
    if data.get("waybar_output") is not None and not isinstance(data["waybar_output"], str):
        raise ValueError(f"{path}: waybar_output must be a connector name or null")
    validate_appearance(data.get("appearance", {}))
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


def prefer_recorded_checkout():
    """Run the checkout recorded at install time when this file is the deployed copy."""
    if os.environ.get("VOLUTA_SKIP_CHECKOUT_REEXEC") == "1":
        return
    try:
        data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "voluta"
        state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "voluta"
        if ROOT.resolve() != (data / "current").resolve() or not (state / "install.json").is_file():
            return
        recorded = json.loads((state / "install.json").read_text(encoding="utf-8")).get("source") or ""
        if not recorded:
            return
        source = Path(recorded)
        target = source / "voluta" / "cli.py"
        if not target.is_file() or source.resolve() == ROOT.resolve():
            return
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return
    env = {**os.environ, "VOLUTA_SKIP_CHECKOUT_REEXEC": "1"}
    python = "/usr/bin/python3" if Path("/usr/bin/python3").is_file() else sys.executable
    os.execve(python, [python, str(target), *sys.argv[1:]], env)


def main(argv=None):
    # Hyprland and Dolphin invoke this file from the deployment tree. Follow the
    # checkout first so a pull is visible before argparse rejects new commands.
    if argv is None:
        prefer_recorded_checkout()
    parser = argparse.ArgumentParser(prog="voluta", description=__doc__)
    parser.add_argument("--config-dir", type=Path, default=config_home())
    parser.add_argument("--host", default=socket.gethostname())
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="create empty overrides; never overwrite settings")
    init.add_argument("--preserve-session", action="store_true", help="retain legacy session restoration")
    commands.add_parser("show", help="show resolved settings")
    commands.add_parser("render-lua", help="render preferences for the compositor")
    get = commands.add_parser("get", help="read a resolved setting as JSON")
    get.add_argument("key")
    commands.add_parser("shell-env", help="render safely quoted login environment")
    for name in ("install", "update"):
        install = commands.add_parser(name, help="deploy/update managed Arch configuration")
        install.add_argument("--skip-deps", action="store_true")
        install.add_argument("--dry-run", action="store_true")
        install.add_argument("--no-session-refresh", action="store_true",
                             help="deploy files without reloading Hyprland, Waybar, and SwayNC")
    commands.add_parser("uninstall", help="restore files replaced by the installer")
    system_setup = commands.add_parser("system-setup", help="install/remove privileged optional integration")
    system_setup.add_argument("module", choices=("sddm", "rgb"))
    system_setup.add_argument("--disable", action="store_true")
    commands.add_parser("rice-switch", help="toggle a configured external rice without deleting config")
    commands.add_parser("doctor", help="check configuration, dependencies and device access")
    commands.add_parser("deps", help="install or repair dependencies without deploying configuration")
    commands.add_parser("apply", help="activate enabled integrations and refresh managed config")
    rgb = commands.add_parser("rgb", help="apply Wallust lighting to selected devices")
    rgb.add_argument("action", nargs="?", choices=("apply", "list", "menu", "select"), default="apply")
    rgb.add_argument("preset", nargs="?", help="preset ID for select; see rgb list")
    rgb.add_argument("--target", choices=("all", "keyboard", "mouse"))
    rgb.add_argument("--dry-run", action="store_true")
    rgb.add_argument("--force", action="store_true")
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
    theme = commands.add_parser("theme", help="set/reset shared appearance preferences")
    theme.add_argument("action", choices=("set", "reset"))
    theme.add_argument("key", help="background.source or background.darken")
    theme.add_argument("value", nargs="?", help="JSON value")
    theme.add_argument("--scope", choices=("shared", "host"), default="shared")
    companion = commands.add_parser("companion", help="attach a local companion settings directory")
    companion.add_argument("action", choices=("attach",))
    companion.add_argument("path", type=Path)
    args = parser.parse_args(argv)
    directory = args.config_dir.expanduser().absolute()
    host = hostname(args.host)
    if args.command == "rgb":
        from rgb_menu import dispatch
        return dispatch(args, directory, host)
    if args.command in ("install", "update", "uninstall", "doctor", "deps", "apply", "rgb", "system-setup", "rice-switch"):
        from deploy import dispatch
        return dispatch(args, directory, host)
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
    if args.command in ("init", "config", "theme") or (args.command == "feature" and args.action != "list"):
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
                if args.command == "theme" and args.key not in ("background.source", "background.darken"):
                    raise ValueError("use background.source or background.darken")
                node = data.setdefault("appearance" if args.command == "theme" else "hyprland", {})
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
            if args.command == "theme":
                validate_appearance(data["appearance"])
            atomic_write(path, data)
        effective, _ = resolve(directory, host)
        if args.command == "feature":
            from deploy import reconcile_if_installed
            try:
                reconcile_if_installed(directory, host)
            except Exception as error:
                print(f"voluta: selection saved; activation needs attention: {error}", file=sys.stderr)
                return 2
        if args.command == "feature" and args.name in ("obs", "rice_switch", "rgb") and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            import subprocess
            subprocess.run(["hyprctl", "reload"], check=False, timeout=10, stdout=subprocess.DEVNULL)
        if args.command == "feature":
            print(f"{args.name}: effective={str(effective['features'][args.name]).lower()} ({args.scope} override updated)")
            print("Session changes are picked up by the login supervisor; Dolphin changes apply on next launch.")
        elif args.command == "theme":
            print("Theme preference saved; refresh the wallpaper palette to apply it")
        else:
            print("Override saved; reload Hyprland to apply it")
        return 0
    settings, initialized = resolve(directory, host)
    if args.command == "get":
        value = settings
        for key in args.key.split("."):
            value = value[key]
        print(json.dumps(value))
    elif args.command == "shell-env":
        import shlex
        for key, value in settings.get("environment", {}).items():
            print(f"unset {key}" if value is None else f"export {key}={shlex.quote(value)}")
    elif args.command == "show":
        print(json.dumps({"initialized": initialized, "host": host, **settings}, indent=2, ensure_ascii=False))
    elif args.command == "render-lua":
        print("return " + lua({"initialized": initialized, "personal_dir": str(directory), "host": host, **settings}))
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
    except (OSError, ValueError, TypeError, KeyError, RecursionError) as error:
        print(f"voluta: {error}", file=sys.stderr)
        raise SystemExit(2)
