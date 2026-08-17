from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from enum import Enum

from Generator.yaml_utils import (
    ConfigError,
    YamlMapping,
    read_boolean,
    read_integer,
    read_mapping,
    read_optional_mapping,
    read_string,
    read_value,
    require_integer,
    validate_sv_identifier,
    value_path,
)


class RegionType(Enum):
    MEMORY = "memory"
    IO = "io"

    @classmethod
    def parse(cls, value: object, path: str) -> "RegionType":
        try:
            return cls(value)
        except (TypeError, ValueError) as exc:
            choices = ", ".join(item.value for item in cls)
            raise ConfigError(f"{path} must be one of: {choices}") from exc

    @property
    def memory_map_type(self) -> str:
        return "MMT_IO" if self is RegionType.IO else "MMT_MEMORY"


class Translation(Enum):
    RELATIVE = "relative"
    LOW_BITS = "low_bits"

    @classmethod
    def parse(cls, value: object, path: str) -> "Translation":
        try:
            return cls(value)
        except (TypeError, ValueError) as exc:
            choices = " or ".join(repr(item.value) for item in cls)
            raise ConfigError(f"{path} must be {choices}") from exc


@dataclass(frozen=True)
class RegionConstantNames:
    logical_prefix: str
    physical_prefix: str

    @classmethod
    def from_yaml(
        cls,
        values: YamlMapping,
        path: str,
    ) -> "RegionConstantNames":
        logical_prefix = validate_sv_identifier(
            read_string(values, "logical_prefix", path),
            value_path(path, "logical_prefix"),
        )
        physical_prefix = validate_sv_identifier(
            read_string(values, "physical_prefix", path),
            value_path(path, "physical_prefix"),
        )
        return cls(logical_prefix, physical_prefix)


@dataclass(frozen=True)
class Register:
    name: str
    offset: int

    @classmethod
    def from_yaml(
        cls,
        name: str,
        value: object,
        region_size: int,
        path: str,
    ) -> "Register":
        validate_sv_identifier(name, path)
        offset = require_integer(value, path)
        if not 0 <= offset < region_size:
            raise ConfigError(f"{path} must be within the region size")
        return cls(name, offset)


@dataclass(frozen=True)
class Region:
    key: str
    region_type: RegionType
    name: str
    constants: RegionConstantNames
    logical_base: int
    physical_base: int
    size: int
    address_bit_width: int
    translation: Translation
    uncachable: bool
    registers: tuple[Register, ...]

    @classmethod
    def from_yaml(
        cls,
        key: str,
        values: YamlMapping,
        path: str,
        raw_address_width: int,
    ) -> "Region":
        region_type = RegionType.parse(
            read_value(values, "type", path),
            value_path(path, "type"),
        )
        logical_base = read_integer(values, "logical_base", path)
        physical_base = read_integer(values, "physical_base", path)
        size = read_integer(values, "size", path)
        translation = Translation.parse(
            read_value(values, "translation", path),
            value_path(path, "translation"),
        )

        cls.validate_base_values(
            logical_base,
            physical_base,
            size,
            raw_address_width,
            path,
        )
        address_bit_width = cls.resolve_address_bit_width(
            values,
            path,
            region_type,
            translation,
            logical_base,
            size,
            raw_address_width,
        )
        register_values = read_optional_mapping(values, "registers", path)
        if region_type is not RegionType.IO and register_values is not None:
            raise ConfigError(
                f"{value_path(path, 'registers')} is only valid for io regions"
            )
        region = cls(
            key=key,
            region_type=region_type,
            name=read_string(values, "name", path, key.upper()),
            constants=RegionConstantNames.from_yaml(
                read_mapping(values, "constants", path),
                value_path(path, "constants"),
            ),
            logical_base=logical_base,
            physical_base=physical_base,
            size=size,
            address_bit_width=address_bit_width,
            translation=translation,
            uncachable=read_boolean(
                values,
                "uncachable",
                path,
                region_type is RegionType.IO,
            ),
            registers=cls.parse_registers(
                register_values,
                size,
                value_path(path, "registers"),
            ),
        )
        region.validate_translation_window(path)
        region.validate_physical_range(raw_address_width, path)
        return region

    @staticmethod
    def validate_base_values(
        logical_base: int,
        physical_base: int,
        size: int,
        raw_address_width: int,
        path: str,
    ) -> None:
        if logical_base < 0:
            raise ConfigError(f"{path}.logical_base must not be negative")
        if physical_base < 0:
            raise ConfigError(f"{path}.physical_base must not be negative")
        if size <= 0:
            raise ConfigError(f"{path}.size must be positive")
        if logical_base + size > 1 << 32:
            raise ConfigError(f"{path} logical address range does not fit in ADDR_WIDTH")
        if physical_base >= 1 << raw_address_width:
            raise ConfigError(
                f"{path}.physical_base does not fit in PHY_RAW_ADDR_WIDTH"
            )

    @staticmethod
    def resolve_address_bit_width(
        values: YamlMapping,
        path: str,
        region_type: RegionType,
        translation: Translation,
        logical_base: int,
        size: int,
        raw_address_width: int,
    ) -> int:
        if "addr_bit_width" in values:
            width = read_integer(values, "addr_bit_width", path)
        elif region_type is RegionType.IO:
            width = (size - 1).bit_length()
        elif translation is Translation.LOW_BITS:
            raw_mask = (1 << raw_address_width) - 1
            width = max(1, ((logical_base & raw_mask) + size - 1).bit_length())
        else:
            width = max(1, (size - 1).bit_length())

        if width < 0:
            raise ConfigError(
                f"{value_path(path, 'addr_bit_width')} must not be negative"
            )
        if width > raw_address_width:
            raise ConfigError(
                f"{value_path(path, 'addr_bit_width')} must not exceed "
                "PHY_RAW_ADDR_WIDTH"
            )
        return width

    @staticmethod
    def parse_registers(
        values: YamlMapping | None,
        region_size: int,
        path: str,
    ) -> tuple[Register, ...]:
        if values is None:
            return ()
        return tuple(
            Register.from_yaml(
                name,
                value,
                region_size,
                value_path(path, name),
            )
            for name, value in values.items()
        )

    @property
    def logical_end(self) -> int:
        return self.logical_base + self.size

    @property
    def is_io(self) -> bool:
        return self.region_type is RegionType.IO

    @property
    def translation_offset(self) -> int:
        if self.translation is Translation.RELATIVE:
            return 0
        return self.logical_base & ((1 << self.address_bit_width) - 1)

    @property
    def physical_range(self) -> tuple[int, int]:
        begin = self.physical_base + self.translation_offset
        return begin, begin + self.size - 1

    def validate_translation_window(self, path: str) -> None:
        if self.translation is not Translation.LOW_BITS:
            return
        window_size = 1 << self.address_bit_width
        if self.translation_offset + self.size > window_size:
            raise ConfigError(
                f"{path} does not fit in its low_bits translation window"
            )
        if self.is_io and self.translation_offset != 0:
            raise ConfigError(
                f"{path}.logical_base must be aligned to the low_bits translation window"
            )

    def validate_physical_range(self, raw_address_width: int, path: str) -> None:
        _, end = self.physical_range
        if end >= 1 << raw_address_width:
            raise ConfigError(
                f"{path} physical address range does not fit in PHY_RAW_ADDR_WIDTH"
            )

    def logical_constant(self, suffix: str) -> str:
        return f"{self.constants.logical_prefix}_{suffix}"

    def physical_constant(self, suffix: str) -> str:
        return f"{self.constants.physical_prefix}_{suffix}"

    def generated_constant_names(self) -> Iterator[str]:
        yield self.logical_constant("BASE")
        yield self.logical_constant("BEGIN")
        yield self.logical_constant("END")
        yield self.logical_constant("ADDR_BIT_WIDTH")
        yield self.physical_constant("BASE")
        for register in self.registers:
            yield self.logical_constant(register.name)
            yield self.physical_constant(register.name)
