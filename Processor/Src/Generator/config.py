from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from Generator.region import Region, RegionType
from Generator.yaml_utils import (
    ConfigError,
    YamlMapping,
    load_yaml,
    read_boolean,
    read_integer,
    read_mapping,
    read_value,
    require_mapping,
    value_path,
)


@dataclass(frozen=True)
class RequiredRegionSpec:
    key: str
    region_type: RegionType
    registers: tuple[str, ...] = ()

    def validate(self, regions: YamlMapping, path: str) -> None:
        region_path = value_path(path, self.key)
        region = read_mapping(regions, self.key, path)
        actual_type = RegionType.parse(
            read_value(region, "type", region_path),
            value_path(region_path, "type"),
        )
        if actual_type is not self.region_type:
            raise ConfigError(
                f"{value_path(region_path, 'type')} must be {self.region_type.value}"
            )

        if not self.registers:
            return
        registers_path = value_path(region_path, "registers")
        registers = read_mapping(region, "registers", region_path)
        for register in self.registers:
            read_value(registers, register, registers_path)


REQUIRED_REGIONS = (
    RequiredRegionSpec("rom", RegionType.MEMORY),
    RequiredRegionSpec("ram", RegionType.MEMORY),
    RequiredRegionSpec("serial", RegionType.IO, ("OUTPUT",)),
    RequiredRegionSpec("timer", RegionType.IO, ("LOW", "HI", "CMP_LOW", "CMP_HI")),
)


@dataclass(frozen=True)
class PcConfig:
    narrow: bool
    width: int

    @classmethod
    def from_yaml(cls, values: YamlMapping, path: str) -> "PcConfig":
        narrow = read_boolean(values, "narrow", path, True)
        width = read_integer(values, "width", path, 19)
        if not 2 <= width <= 32:
            raise ConfigError(
                f"{value_path(path, 'width')} must be between 2 and 32"
            )
        return cls(narrow, width)


@dataclass(frozen=True)
class MemoryMapConfig:
    physical_address_width: int
    pc: PcConfig
    regions: tuple[Region, ...]

    @classmethod
    def from_yaml(cls, values: YamlMapping, path: str) -> "MemoryMapConfig":
        physical_address_width = read_integer(
            values,
            "physical_address_width",
            path,
        )
        if physical_address_width <= 2:
            raise ConfigError(
                f"{value_path(path, 'physical_address_width')} must be greater than 2"
            )
        raw_address_width = physical_address_width - 2

        regions_path = value_path(path, "regions")
        region_values = read_mapping(values, "regions", path)
        for required_region in REQUIRED_REGIONS:
            required_region.validate(region_values, regions_path)

        regions = tuple(
            Region.from_yaml(
                key,
                require_mapping(value, value_path(regions_path, key)),
                value_path(regions_path, key),
                raw_address_width,
            )
            for key, value in region_values.items()
        )
        pc_path = value_path(path, "pc")
        config = cls(
            physical_address_width,
            PcConfig.from_yaml(read_mapping(values, "pc", path), pc_path),
            regions,
        )
        config.validate()
        return config

    @property
    def raw_address_width(self) -> int:
        return self.physical_address_width - 2

    def validate(self) -> None:
        self.validate_logical_ranges()
        self.validate_constant_names()

    def validate_logical_ranges(self) -> None:
        sorted_regions = sorted(self.regions, key=lambda region: region.logical_base)
        for previous, current in zip(sorted_regions, sorted_regions[1:]):
            if current.logical_base < previous.logical_end:
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


@dataclass(frozen=True)
class CpuConfig:
    instruction_reset_vector: int
    pc_goal: int
    memory_map: MemoryMapConfig

    @classmethod
    def from_yaml(cls, values: YamlMapping, path: str = "config") -> "CpuConfig":
        memory_map_path = value_path(path, "memory_map")
        return cls(
            instruction_reset_vector=read_integer(
                values,
                "INSN_RESET_VECTOR",
                path,
            ),
            pc_goal=read_integer(values, "PC_GOAL", path),
            memory_map=MemoryMapConfig.from_yaml(
                read_mapping(values, "memory_map", path),
                memory_map_path,
            ),
        )


def load_config(path: Path) -> CpuConfig:
    return CpuConfig.from_yaml(load_yaml(path))
