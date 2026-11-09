from __future__ import annotations

import re
from collections.abc import Mapping
from pathlib import Path

import yaml


class ConfigError(Exception):
    pass


YamlMapping = Mapping[str, object]

_MISSING = object()
_SV_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*\Z")


def validate_keys(values: YamlMapping, allowed: tuple[str, ...], path: str) -> None:
    unknown = values.keys() - set(allowed)
    if unknown:
        raise ConfigError(f"{path}: unknown keys: {', '.join(sorted(unknown))}")


class UniqueKeyLoader(yaml.SafeLoader):
    # A misspelled or repeated setting must not silently change the hardware.
    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        values = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            if not isinstance(key, str):
                raise ConfigError("YAML mapping keys must be strings")
            if key in values:
                raise ConfigError(f"duplicate YAML key: {key}")
            values[key] = self.construct_object(value_node, deep=deep)
        return values


def value_path(path: str, key: str) -> str:
    return f"{path}.{key}"


def require_mapping(value: object, path: str) -> YamlMapping:
    if not isinstance(value, Mapping):
        raise ConfigError(f"{path} must be a mapping")
    for key in value:
        if not isinstance(key, str):
            raise ConfigError(f"{path} keys must be strings")
    return value


def read_value(
    values: YamlMapping,
    key: str,
    path: str,
    default: object = _MISSING,
) -> object:
    if key in values:
        return values[key]
    if default is _MISSING:
        raise ConfigError(f"{value_path(path, key)} is required")
    return default


def read_mapping(values: YamlMapping, key: str, path: str) -> YamlMapping:
    child_path = value_path(path, key)
    return require_mapping(read_value(values, key, path), child_path)


def read_optional_mapping(
    values: YamlMapping,
    key: str,
    path: str,
) -> YamlMapping | None:
    if key not in values:
        return None
    return require_mapping(values[key], value_path(path, key))


def read_string(
    values: YamlMapping,
    key: str,
    path: str,
    default: object = _MISSING,
) -> str:
    child_path = value_path(path, key)
    value = read_value(values, key, path, default)
    if not isinstance(value, str):
        raise ConfigError(f"{child_path} must be a string")
    return value


def require_integer(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ConfigError(f"{path} must be a YAML integer")
    return value


def read_integer(
    values: YamlMapping,
    key: str,
    path: str,
    default: object = _MISSING,
) -> int:
    return require_integer(
        read_value(values, key, path, default),
        value_path(path, key),
    )


def read_boolean(
    values: YamlMapping,
    key: str,
    path: str,
    default: object = _MISSING,
) -> bool:
    child_path = value_path(path, key)
    value = read_value(values, key, path, default)
    if not isinstance(value, bool):
        raise ConfigError(f"{child_path} must be a boolean")
    return value


def validate_sv_identifier(value: str, path: str) -> str:
    if not _SV_IDENTIFIER.fullmatch(value):
        raise ConfigError(f"{path} must be a valid SystemVerilog identifier")
    return value


def load_yaml(path: Path) -> YamlMapping:
    try:
        value = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)
    except yaml.YAMLError as exc:
        raise ConfigError(f"{path}: invalid YAML: {exc}") from exc
    return require_mapping(value, "config")
