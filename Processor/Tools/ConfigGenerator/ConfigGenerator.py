#!/usr/bin/env python3
"""Generate RTL and build definitions from Processor/Config/*.toml."""

from __future__ import annotations

import argparse
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
import re
import sys
import tomllib


# TOML loading and validation

class ConfigError(Exception):
    pass


ConfigMapping = Mapping[str, object]

_MISSING = object()


def validate_keys(values: ConfigMapping, allowed: tuple[str, ...], path: str) -> None:
    unknown = values.keys() - set(allowed)
    if unknown:
        raise ConfigError(f"{path}: unknown keys: {', '.join(sorted(unknown))}")


def require_mapping(value: object, path: str) -> ConfigMapping:
    if not isinstance(value, Mapping):
        raise ConfigError(f"{path} must be a mapping")
    for key in value:
        if not isinstance(key, str):
            raise ConfigError(f"{path} keys must be strings")
    return value


def read_value(values: ConfigMapping, key: str, path: str, default: object = _MISSING) -> object:
    if key in values:
        return values[key]
    if default is _MISSING:
        raise ConfigError(f"{path}.{key} is required")
    return default


def read_mapping(values: ConfigMapping, key: str, path: str) -> ConfigMapping:
    child_path = f"{path}.{key}"
    return require_mapping(read_value(values, key, path), child_path)


def read_optional_mapping(values: ConfigMapping, key: str, path: str) -> ConfigMapping | None:
    if key not in values:
        return None
    return require_mapping(values[key], f"{path}.{key}")


def read_string(values: ConfigMapping, key: str, path: str, default: object = _MISSING) -> str:
    child_path = f"{path}.{key}"
    value = read_value(values, key, path, default)
    if not isinstance(value, str):
        raise ConfigError(f"{child_path} must be a string")
    return value


def require_integer(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ConfigError(f"{path} must be an integer")
    return value


def read_integer(values: ConfigMapping, key: str, path: str, default: object = _MISSING) -> int:
    return require_integer(read_value(values, key, path, default), f"{path}.{key}")


def read_boolean(values: ConfigMapping, key: str, path: str, default: object = _MISSING) -> bool:
    child_path = f"{path}.{key}"
    value = read_value(values, key, path, default)
    if not isinstance(value, bool):
        raise ConfigError(f"{child_path} must be a boolean")
    return value


def load_toml(path: Path) -> ConfigMapping:
    try:
        with path.open("rb") as source:
            value = tomllib.load(source)
    except tomllib.TOMLDecodeError as exc:
        raise ConfigError(f"{path}: invalid TOML: {exc}") from exc
    return require_mapping(value, "config")


# Memory regions and address translation

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
class Register:
    name: str
    offset: int

    @classmethod
    def from_mapping(cls, name: str, value: object, region_size: int, path: str) -> "Register":
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            raise ConfigError(f"{path} must be a valid C/SystemVerilog identifier")
        offset = require_integer(value, path)
        if not 0 <= offset < region_size:
            raise ConfigError(f"{path} must be within the region size")
        return cls(name, offset)


@dataclass(frozen=True)
class Region:
    key: str
    region_type: RegionType
    name: str
    logical_base: int
    physical_base: int
    size: int
    address_bit_width: int
    translation: Translation
    uncachable: bool
    registers: tuple[Register, ...]

    @classmethod
    def from_mapping(cls, key: str, values: ConfigMapping, path: str,
                  raw_address_width: int) -> "Region":
        if not re.fullmatch(r"[a-z][a-z0-9_]*", key):
            raise ConfigError(f"{path}: region keys must use lowercase letters, digits and underscores")
        validate_keys(values, (
            "type", "name", "logical_base", "physical_base", "size",
            "translation", "addr_bit_width", "uncachable", "registers",
        ), path)
        region_type = RegionType.parse(read_value(values, "type", path), f"{path}.type")
        logical_base = read_integer(values, "logical_base", path)
        physical_base = read_integer(values, "physical_base", path)
        size = read_integer(values, "size", path)
        translation = Translation.parse(
            read_value(values, "translation", path),
            f"{path}.translation",
        )

        cls.validate_base_values(logical_base, physical_base, size, raw_address_width, path)
        address_bit_width = cls.resolve_address_bit_width(
            values, path, region_type, translation, logical_base, size, raw_address_width,
        )
        register_values = read_optional_mapping(values, "registers", path)
        if region_type is not RegionType.IO and register_values is not None:
            raise ConfigError(f"{path}.registers is only valid for io regions")
        name = read_string(values, "name", path, key.upper())
        region = cls(
            key=key,
            region_type=region_type,
            name=name,
            logical_base=logical_base,
            physical_base=physical_base,
            size=size,
            address_bit_width=address_bit_width,
            translation=translation,
            uncachable=read_boolean(values, "uncachable", path, region_type is RegionType.IO),
            registers=cls.parse_registers(register_values, size, f"{path}.registers"),
        )
        region.validate_translation_window(path)
        region.validate_physical_range(raw_address_width, path)
        return region

    @staticmethod
    def validate_base_values(logical_base: int, physical_base: int, size: int,
                             raw_address_width: int, path: str) -> None:
        if logical_base < 0:
            raise ConfigError(f"{path}.logical_base must not be negative")
        if physical_base < 0:
            raise ConfigError(f"{path}.physical_base must not be negative")
        if size <= 0:
            raise ConfigError(f"{path}.size must be positive")
        # END includes the last valid address, which must fit in ADDR_WIDTH.
        if logical_base + size - 1 >= (1 << 32):
            raise ConfigError(f"{path} logical address range does not fit in ADDR_WIDTH")
        if physical_base >= 1 << raw_address_width:
            raise ConfigError(f"{path}.physical_base does not fit in PHY_RAW_ADDR_WIDTH")

    @staticmethod
    def resolve_address_bit_width(values: ConfigMapping, path: str, region_type: RegionType,
                                  translation: Translation, logical_base: int, size: int,
                                  raw_address_width: int) -> int:
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
            raise ConfigError(f"{path}.addr_bit_width must not be negative")
        if width > raw_address_width:
            raise ConfigError(f"{path}.addr_bit_width must not exceed PHY_RAW_ADDR_WIDTH")
        return width

    @staticmethod
    def parse_registers(values: ConfigMapping | None, region_size: int,
                        path: str) -> tuple[Register, ...]:
        if values is None:
            return ()
        return tuple(
            Register.from_mapping(name, value, region_size, f"{path}.{name}")
            for name, value in values.items()
        )

    @property
    def logical_end(self) -> int:
        return self.logical_base + self.size - 1

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
            raise ConfigError(f"{path} does not fit in its low_bits translation window")
        if self.is_io and self.translation_offset != 0:
            raise ConfigError(
                f"{path}.logical_base must be aligned to the low_bits translation window"
            )

    def validate_physical_range(self, raw_address_width: int, path: str) -> None:
        _, end = self.physical_range
        if end >= 1 << raw_address_width:
            raise ConfigError(f"{path} physical address range does not fit in PHY_RAW_ADDR_WIDTH")

    @property
    def logical_prefix(self) -> str:
        return f"LOG_ADDR_{self.key.upper()}"

    @property
    def physical_prefix(self) -> str:
        return f"PHY_ADDR_{self.key.upper()}"

    def logical_constant(self, suffix: str) -> str:
        return f"{self.logical_prefix}_{suffix}"

    def physical_constant(self, suffix: str) -> str:
        return f"{self.physical_prefix}_{suffix}"

    def generated_constant_names(self) -> Iterator[str]:
        yield self.logical_constant("BASE")
        yield self.logical_constant("BEGIN")
        yield self.logical_constant("END")
        yield self.logical_constant("ADDR_BIT_WIDTH")
        yield self.physical_constant("BASE")
        yield self.physical_constant("END")
        for register in self.registers:
            yield self.logical_constant(register.name)
            yield self.physical_constant(register.name)


# Configuration and cross-region validation

# These names and registers are referenced directly by the RTL.
REQUIRED_REGIONS = (
    ("rom", RegionType.MEMORY, ()),
    ("ram", RegionType.MEMORY, ()),
    ("serial", RegionType.IO, ("OUTPUT",)),
    ("clint", RegionType.IO,
     ("MSIP", "TIMER_LOW", "TIMER_HI", "TIMER_CMP_LOW", "TIMER_CMP_HI")),
    ("plic", RegionType.IO,
     ("SOURCE_PRIORITY_BASE", "PENDING_BASE", "ENABLE_BASE",
      "PRIORITY_THRESHOLD_BASE", "CLAIM_COMPLETE_BASE")),
)


def validate_required_regions(regions: ConfigMapping, path: str) -> None:
    for key, region_type, required_registers in REQUIRED_REGIONS:
        region_path = f"{path}.{key}"
        region = read_mapping(regions, key, path)
        actual_type = RegionType.parse(read_value(region, "type", region_path), f"{region_path}.type")
        if actual_type is not region_type:
            raise ConfigError(f"{region_path}.type must be {region_type.value}")
        if required_registers:
            registers = read_mapping(region, "registers", region_path)
            for register in required_registers:
                read_value(registers, register, f"{region_path}.registers")


@dataclass(frozen=True)
class ProcessorConfig:
    instruction_reset_vector: int
    pc_goal: int
    physical_address_width: int
    pc_narrow: bool
    pc_width: int
    regions: tuple[Region, ...]

    @classmethod
    def from_mapping(cls, values: ConfigMapping, path: str = "config") -> "ProcessorConfig":
        validate_keys(values, ("insn_reset_vector", "pc_goal", "memory_map"), path)
        reset_vector = read_integer(values, "insn_reset_vector", path)
        pc_goal = read_integer(values, "pc_goal", path)
        map_path = f"{path}.memory_map"
        memory_map = read_mapping(values, "memory_map", path)
        validate_keys(memory_map, ("physical_address_width", "pc", "regions"), map_path)
        physical_width = read_integer(memory_map, "physical_address_width", map_path)
        if not 3 <= physical_width <= 34:
            raise ConfigError(f"{map_path}.physical_address_width must be between 3 and 34")
        regions_path = f"{map_path}.regions"
        region_values = read_mapping(memory_map, "regions", map_path)
        validate_required_regions(region_values, regions_path)
        regions = tuple(
            Region.from_mapping(key, require_mapping(value, f"{regions_path}.{key}"),
                             f"{regions_path}.{key}", physical_width - 2)
            for key, value in region_values.items()
        )
        pc_path = f"{map_path}.pc"
        pc = read_mapping(memory_map, "pc", map_path)
        validate_keys(pc, ("narrow", "width"), pc_path)
        pc_narrow = read_boolean(pc, "narrow", pc_path, True)
        pc_width = read_integer(pc, "width", pc_path, 19)
        if not 2 <= pc_width <= 32:
            raise ConfigError(f"{pc_path}.width must be between 2 and 32")
        config = cls(reset_vector, pc_goal, physical_width, pc_narrow, pc_width, regions)
        config.validate_logical_ranges()
        config.validate_constant_names()
        for name, addr in (("insn_reset_vector", reset_vector), ("pc_goal", pc_goal)):
            if not 0 <= addr < (1 << 32) or addr % 4:
                raise ConfigError(f"{name} must be an aligned RV32 instruction address")
            if not any(not r.is_io and r.logical_base <= addr <= r.logical_end for r in regions):
                raise ConfigError(f"{name} must be in a memory region")
        if pc_narrow:
            # Compression drops all bits between the sign bit and the low PC bits.
            mask = ((1 << 31) - 1) & ~((1 << (pc_width - 1)) - 1)
            for region in regions:
                if not region.is_io and (region.logical_base & mask or
                                        region.logical_end & mask or
                                        region.size > (1 << (pc_width - 1))):
                    raise ConfigError(f"memory region {region.key} does not fit the narrow PC")
        return config

    @property
    def raw_address_width(self) -> int:
        return self.physical_address_width - 2

    @property
    def memory_byte_size(self) -> int:
        # IO has a separate address space and consumes no backing RAM.
        return max(region.physical_range[1] + 1 for region in self.regions if not region.is_io)

    def validate_logical_ranges(self) -> None:
        sorted_regions = sorted(self.regions, key=lambda region: region.logical_base)
        for previous, current in zip(sorted_regions, sorted_regions[1:]):
            if current.logical_base <= previous.logical_end:
                raise ConfigError(
                    f"logical address regions overlap: {previous.key} and {current.key}"
                )

    def validate_constant_names(self) -> None:
        owners: dict[str, str] = {}
        for region in self.regions:
            for constant_name in region.generated_constant_names():
                if constant_name in owners:
                    raise ConfigError(
                        f"generated constant {constant_name} is shared by "
                        f"regions {owners[constant_name]} and {region.key}"
                    )
                owners[constant_name] = region.key


def load_config(path: Path) -> ProcessorConfig:
    return ProcessorConfig.from_mapping(load_toml(path))


# RTL and software output

def grouped_hex(value: int, bits: int) -> str:
    if value < 0:
        raise ConfigError("negative address values are not supported")
    digits = f"{value:0{max(1, (bits + 3) // 4)}x}"
    first_group = len(digits) % 4
    groups = [digits[:first_group]] if first_group else []
    groups.extend(digits[index:index + 4] for index in range(first_group, len(digits), 4))
    return "_".join(groups)


def sized_hex_literal(value: int, bits: int) -> str:
    if not 0 <= value < 1 << bits:
        raise ConfigError(f"value {value} does not fit in {bits} bits")
    digits = f"{value:0{max(1, (bits + 3) // 4)}x}"
    return f"{bits}'h{digits}"


_PLACEHOLDER = re.compile(r"{{\s*([A-Za-z0-9_]+)\s*}}")


@dataclass(frozen=True)
class MemoryMapRenderer:
    config: ProcessorConfig
    config_path: Path
    template_path: Path

    def render(self, template: str) -> str:
        replacements = {
            "GENERATED_NOTICE": (
                "// This file is generated by Tools/ConfigGenerator/ConfigGenerator.py from "
                f"Config/{self.config_path.name} and {self.template_source_name()}.\n"
                "// Do not edit this file directly."
            ),
            "INSN_RESET_VECTOR": sized_hex_literal(self.config.instruction_reset_vector, 32),
            "PC_GOAL": sized_hex_literal(self.config.pc_goal, 32),
            "RSD_NARROW_PC_DEFINE": (
                "`define RSD_NARROW_PC" if self.config.pc_narrow else ""
            ),
            "PC_WIDTH": str(self.config.pc_width),
            "PHY_ADDR_WIDTH": str(self.config.physical_address_width),
            "MEMORY_MAP_DOC": self.render_memory_map_doc(),
            "MEMORY_MAP_CONSTANTS": self.render_region_constants(),
            "GET_MEMORY_MAP_TYPE_BODY": self.render_get_memory_map_type(),
            "TO_PHY_ADDR_FROM_LOGICAL_BODY": self.render_to_physical_address(),
        }
        placeholders = set(_PLACEHOLDER.findall(template))
        missing = placeholders - replacements.keys()
        unused = replacements.keys() - placeholders
        if missing or unused:
            raise ConfigError(f"template placeholders differ: unknown={sorted(missing)}, missing={sorted(unused)}")
        return _PLACEHOLDER.sub(lambda match: replacements[match.group(1)], template)

    def template_source_name(self) -> str:
        try:
            return self.template_path.relative_to(self.config_path.parent.parent).as_posix()
        except ValueError:
            return self.template_path.as_posix()

    def render_memory_map_doc(self) -> str:
        return "\n".join(
            f"//       0x{grouped_hex(region.logical_base, 32)} "
            f"--0x{grouped_hex(region.logical_end, 32)}: "
            f"{region.name}"
            for region in self.config.regions
        )

    def render_region_constants(self) -> str:
        return ("// Backing memory must cover the translated addresses, including holes.\n"
                f"localparam MEMORY_MAP_BYTE_SIZE = {sized_hex_literal(self.config.memory_byte_size, 33)};\n\n") + "\n\n".join(
            self.render_single_region_constants(region)
            for region in self.config.regions
        )

    def software_constants(self) -> dict[str, int]:
        constants = {"RSD_RESET_VECTOR": self.config.instruction_reset_vector,
                     "RSD_PC_GOAL": self.config.pc_goal}
        for region in self.config.regions:
            prefix = f"RSD_{region.key.upper()}"
            values = {f"{prefix}_BASE": region.logical_base,
                      f"{prefix}_SIZE": region.size,
                      f"{prefix}_END": region.logical_end,
                      f"{prefix}_PHYSICAL_BASE": region.physical_range[0],
                      f"{prefix}_PHYSICAL_END": region.physical_range[1]}
            for register in region.registers:
                name = f"{prefix}_{register.name}"
                if name in values:
                    raise ConfigError(f"duplicate software constant: {name}")
                values[name] = region.logical_base + register.offset
            if constants.keys() & values.keys():
                raise ConfigError(f"duplicate software constants for region {region.key}")
            constants.update(values)
        return constants

    def render_software(self) -> dict[str, str]:
        constants = self.software_constants()
        notice = "Generated from Config/MemoryMap.toml by Tools/ConfigGenerator/ConfigGenerator.py. Do not edit."
        # DTS unit addresses are tokens without the 0x prefix used by C/assembly.
        unit_addresses = {}
        for name in ("RSD_ROM_BASE", "RSD_RAM_BASE", "RSD_CLINT_TIMER_LOW"):
            if name + "_HEX" in constants:
                raise ConfigError(f"reserved DTS constant: {name}_HEX")
            unit_addresses[name + "_HEX"] = constants[name]
        return {
            "rsd-memory-map.h": (
                f"/* {notice} */\n#ifndef RSD_MEMORY_MAP_H\n#define RSD_MEMORY_MAP_H\n"
                + "".join(f"#define {key} 0x{value:x}\n" for key, value in constants.items())
                + "/* Hexadecimal tokens without 0x for DTS unit addresses. */\n"
                + "".join(f"#define {key} {value:x}\n" for key, value in unit_addresses.items())
                + "#endif\n"
            ),
            "rsd-memory-map.ld": f"/* {notice} */\n" +
                "".join(f"{key} = 0x{value:x};\n" for key, value in constants.items()),
            "rsd-memory-map.mk": f"# {notice}\n" +
                "".join(f"{key} := {value}\n" for key, value in constants.items()),
        }

    def render_single_region_constants(self, region: Region) -> str:
        logical_prefix = region.logical_prefix
        physical_prefix = region.physical_prefix
        physical_begin, physical_end = region.physical_range
        raw_width = self.config.raw_address_width
        lines = [
            "//",
            f"// {region.name}",
            f"// logical [0x{grouped_hex(region.logical_base, 32)} - "
            f"0x{grouped_hex(region.logical_end, 32)}] -> physical "
            f"[0x{grouped_hex(physical_begin, raw_width)} - "
            f"0x{grouped_hex(physical_end, raw_width)}]",
            "//",
            f"localparam {logical_prefix}_BASE = "
            f"ADDR_WIDTH'('h{grouped_hex(region.logical_base, 32)});",
        ]
        for register in region.registers:
            lines.append(
                f"localparam {logical_prefix}_{register.name:<7} = "
                f"{logical_prefix}_BASE + {register.offset};"
            )
        lines.extend(
            [
                f"localparam {logical_prefix}_BEGIN = {logical_prefix}_BASE;",
                f"localparam {logical_prefix}_END   = "
                f"{logical_prefix}_BASE + ({region.size} - 1);",
                f"localparam {logical_prefix}_ADDR_BIT_WIDTH = "
                f"{region.address_bit_width};",
                f"localparam {physical_prefix}_BASE = "
                f"PHY_RAW_ADDR_WIDTH'('h{grouped_hex(region.physical_base, raw_width)});",
                # END is the last address and uses the same width as BASE.
                f"localparam {physical_prefix}_END   = "
                f"PHY_RAW_ADDR_WIDTH'('h{grouped_hex(physical_end, raw_width)});",
            ]
        )
        for register in region.registers:
            lines.append(
                f"localparam {physical_prefix}_{register.name:<7} = "
                + self.translation_expression(region, f"{logical_prefix}_{register.name}")
                + ";"
            )
        return "\n".join(lines)

    def render_get_memory_map_type(self) -> str:
        lines: list[str] = []
        for index, region in enumerate(self.config.regions):
            prefix = "if" if index == 0 else "else if"
            lines.extend(
                [
                    f"    {prefix} ({self.range_condition(region, 'addr')}) begin",
                    f"        return {region.region_type.memory_map_type};",
                    "    end",
                ]
            )
        return "\n".join(lines)

    def render_to_physical_address(self) -> str:
        lines: list[str] = []
        for index, region in enumerate(self.config.regions):
            prefix = "if" if index == 0 else "else if"
            lines.append(f"    {prefix} ({self.range_condition(region, 'logAddr')}) begin")
            if not region.is_io:
                lines.append(f"        // {region.name}")
            lines.extend(
                [
                    f"        phyAddr.isUncachable = "
                    f"{'TRUE' if region.uncachable else 'FALSE'};",
                    f"        phyAddr.isIO = {'TRUE' if region.is_io else 'FALSE'};",
                    "        phyAddr.addr = "
                    + self.translation_expression(region, "logAddr")
                    + ";",
                    "    end",
                ]
            )
        return "\n".join(lines)

    @staticmethod
    def range_condition(region: Region, address: str) -> str:
        begin = region.logical_constant("BEGIN")
        end = region.logical_constant("END")
        return f"{begin} <= {address} && {address} <= {end}"

    @staticmethod
    def translation_expression(region: Region, logical_address: str) -> str:
        physical_base = region.physical_constant("BASE")
        if region.translation is Translation.RELATIVE:
            logical_base = region.logical_constant("BEGIN")
            return (
                f"{physical_base} + "
                f"PhyRawAddrPath'({logical_address} - {logical_base})"
            )
        if region.address_bit_width == 0:
            return physical_base

        width = region.logical_constant("ADDR_BIT_WIDTH")
        return f"{physical_base} + PhyRawAddrPath'({logical_address}[{width}-1:0])"


# Microarchitecture defaults shared by RTL, synthesis, and software builds.

MICRO_ARCH_PARAMETERS = (
    "FETCH_WIDTH", "COMMIT_WIDTH", "PSCALAR_NUM", "PSCALAR_FP_NUM",
    "ISSUE_QUEUE_ENTRY_NUM", "ACTIVE_LIST_ENTRY_NUM", "REPLAY_QUEUE_ENTRY_NUM",
    "LOAD_QUEUE_ENTRY_NUM", "STORE_QUEUE_ENTRY_NUM", "BTB_ENTRY_NUM", "PHT_ENTRY_NUM",
    "BRANCH_GLOBAL_HISTORY_BIT_WIDTH", "MDT_ENTRY_NUM",
    "DCACHE_WAY_NUM", "DCACHE_LINE_BYTE_NUM", "DCACHE_MSHR_NUM",
    "ICACHE_WAY_NUM", "ICACHE_LINE_BYTE_NUM",
    "DCACHE_INDEX_BIT_WIDTH_BASE", "ICACHE_INDEX_BIT_WIDTH_BASE", "INT_ISSUE_WIDTH",
)
# The configuration describes settings; preprocessor names are an RTL implementation detail.
MICRO_ARCH_FEATURES = {
    "enable_fp_pipe": "RSD_MARCH_FP_PIPE",
    "enable_zba": "RSD_ENABLE_ZBA",
    "enable_zicond": "RSD_ENABLE_ZICOND",
    "enable_zicfilp": "RSD_ENABLE_ZICFILP",
    "enable_unified_muldiv_mem_pipe": "RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE",
    "enable_unified_ldst_mem_pipe": "RSD_MARCH_UNIFIED_LDST_MEM_PIPE",
}


def validate_micro_arch(parameters: ConfigMapping) -> tuple[dict[str, int], dict[str, str | None]]:
    validate_keys(parameters, (*(name.lower() for name in MICRO_ARCH_PARAMETERS), *MICRO_ARCH_FEATURES,
                               "enable_performance_counter"), "parameters")
    params = {name: read_integer(parameters, name.lower(), "parameters")
              for name in MICRO_ARCH_PARAMETERS}
    for name, value in params.items():
        if not 0 < value < (1 << 31):
            raise ConfigError(f"parameters.{name.lower()} must be a positive signed 32-bit integer")
    # Check known structural constraints, not every possible RTL configuration.
    for name in ("PSCALAR_NUM", "PSCALAR_FP_NUM", "ACTIVE_LIST_ENTRY_NUM",
                 "LOAD_QUEUE_ENTRY_NUM", "STORE_QUEUE_ENTRY_NUM", "BTB_ENTRY_NUM",
                 "PHT_ENTRY_NUM", "MDT_ENTRY_NUM", "DCACHE_WAY_NUM", "ICACHE_WAY_NUM",
                 "DCACHE_LINE_BYTE_NUM", "ICACHE_LINE_BYTE_NUM"):
        if params[name] & (params[name] - 1):
            raise ConfigError(f"parameters.{name.lower()} must be a power of two")
    if params["COMMIT_WIDTH"] < params["FETCH_WIDTH"]:
        raise ConfigError("commit_width must be at least fetch_width for recovery")
    if params["PSCALAR_NUM"] != params["PSCALAR_FP_NUM"]:
        raise ConfigError("pscalar_num and pscalar_fp_num must match")
    if params["PSCALAR_NUM"] <= 32:
        raise ConfigError("pscalar_num must exceed the 32 architectural registers")
    if params["ICACHE_WAY_NUM"] < 2:
        raise ConfigError("icache_way_num must be at least 2")
    if params["BRANCH_GLOBAL_HISTORY_BIT_WIDTH"] > params["PHT_ENTRY_NUM"].bit_length() - 1:
        raise ConfigError("branch_global_history_bit_width must fit the PHT index")
    for cache in ("DCACHE", "ICACHE"):
        bits = params[f"{cache}_INDEX_BIT_WIDTH_BASE"] - (params[f"{cache}_WAY_NUM"].bit_length() - 1)
        if bits < 1 or bits + params[f"{cache}_LINE_BYTE_NUM"].bit_length() - 1 >= 32:
            raise ConfigError(f"{cache.lower()} index and line offset must leave address tag bits")
    width = params["INT_ISSUE_WIDTH"]
    if width not in (1, 2):
        raise ConfigError("int_issue_width must be 1 or 2")
    features = {macro: read_boolean(parameters, name, "parameters")
                for name, macro in MICRO_ARCH_FEATURES.items()}

    macros = {"RSD_MARCH_INT_ISSUE_WIDTH": str(width)}
    macros.update({name: None for name, enabled in features.items() if enabled})
    if not read_boolean(parameters, "enable_performance_counter", "parameters"):
        macros["RSD_DISABLE_PERFORMANCE_COUNTER"] = None
    return params, macros


def render_micro_arch(values: ConfigMapping, template: str) -> dict[str, str]:
    validate_keys(values, ("parameters", "overrides"), "MicroArch")
    parameters = read_mapping(values, "parameters", "MicroArch")
    validate_micro_arch(parameters)
    overrides = read_optional_mapping(values, "overrides", "MicroArch")
    if overrides is None:
        overrides = {}
    validate_keys(overrides, ("simulation", "synthesis"), "overrides")
    configs = {}
    for mode in ("simulation", "synthesis"):
        override = read_optional_mapping(overrides, mode, "overrides")
        if override is None:
            override = {}
        validate_keys(override, tuple(parameters), f"overrides.{mode}")
        configs[mode] = validate_micro_arch({**parameters, **override})

    if set(_PLACEHOLDER.findall(template)) != set(MICRO_ARCH_PARAMETERS):
        raise ConfigError("MicroArchConf template placeholders do not match the settings")
    rtl = []
    for line in template.splitlines(keepends=True):
        sim = _PLACEHOLDER.sub(lambda match: str(configs["simulation"][0][match[1]]), line)
        synth = _PLACEHOLDER.sub(lambda match: str(configs["synthesis"][0][match[1]]), line)
        if sim == synth:
            rtl.append(sim)
        else:
            # Netlist testbenches must use the same widths as the synthesized core.
            rtl.append(f"`ifdef RSD_SYNTHESIS\n{synth}"
                       f"`elsif RSD_POST_SYNTHESIS_SIMULATION\n{synth}"
                       f"`else\n{sim}`endif\n")

    notice = "Generated from Config/MicroArch.toml by Tools/ConfigGenerator/ConfigGenerator.py. Do not edit."
    make_lines = [f"# {notice}"]
    for mode, variable in (("simulation", "RSD_SRC_CFG"), ("synthesis", "RSD_SYNTHESIS_SRC_CFG")):
        flags = " ".join(f"+define+{name}" + (f"={value}" if value is not None else "")
                         for name, value in configs[mode][1].items())
        make_lines.append(f"{variable} = {flags}")
    sv_macros = "\n".join(f"`define {name}" + (f" {value}" if value is not None else "")
                          for name, value in configs["synthesis"][1].items())
    return {
        "Config/MicroArchConf.sv": "".join(rtl),
        "Makefiles/MicroArch.inc.mk": "\n".join(make_lines) + "\n",
        "Config/MicroArchMacros.svh": f"// {notice}\n{sv_macros}\n",
    }


# Command-line entry point

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate RTL and build definitions from Processor/Config/*.toml."
    )
    parser.add_argument("--rsd-root", required=True, type=Path, help="RSD repository root")
    parser.add_argument("--only", choices=("memory-map", "microarch"),
                        help="Generate one configuration group (default: both)")
    args = parser.parse_args()
    processor_root = args.rsd_root / "Processor"
    source_root = processor_root / "Src"
    config_path = processor_root / "Config" / "MemoryMap.toml"
    template_path = source_root / "Config" / "MemoryMapTypes.template.sv"
    output_path = source_root / "Config" / "MemoryMapTypes.sv"

    try:
        outputs = {}
        if args.only in (None, "memory-map"):
            config = load_config(config_path)
            template = template_path.read_text(encoding="utf-8")
            renderer = MemoryMapRenderer(config, config_path, template_path)
            outputs[output_path] = renderer.render(template)
            outputs.update({source_root / "Verification/TestCode" / name: content
                            for name, content in renderer.render_software().items()})
        if args.only in (None, "microarch"):
            values = load_toml(processor_root / "Config/MicroArch.toml")
            template = (source_root / "Config/MicroArchConf.template.sv").read_text(encoding="utf-8")
            outputs.update({source_root / name: content
                            for name, content in render_micro_arch(values, template).items()})
        # Render everything before writing any outputs.
        for path, content in outputs.items():
            # Preserve the existing MicroArchConf.sv line-ending convention.
            path.write_text(content, encoding="utf-8",
                            newline="\r\n" if path.name == "MicroArchConf.sv" else "\n")
    except (ConfigError, OSError) as exc:
        print(f"ConfigGenerator.py: error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
