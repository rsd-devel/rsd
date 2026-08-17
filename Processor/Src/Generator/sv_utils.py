from Generator.yaml_utils import ConfigError


class SystemVerilog:
    @staticmethod
    def boolean(value: bool) -> str:
        return "TRUE" if value else "FALSE"

    @staticmethod
    def grouped_hex(value: int, bits: int) -> str:
        if value < 0:
            raise ConfigError("negative address values are not supported")
        digits = f"{value:0{max(1, (bits + 3) // 4)}x}"
        first_group = len(digits) % 4
        groups = [digits[:first_group]] if first_group else []
        groups.extend(
            digits[index : index + 4]
            for index in range(first_group, len(digits), 4)
        )
        return "_".join(groups)

    @classmethod
    def hex_literal(cls, value: int, bits: int) -> str:
        return f"'h{cls.grouped_hex(value, bits)}"

    @staticmethod
    def sized_hex_literal(value: int, bits: int) -> str:
        if not 0 <= value < 1 << bits:
            raise ConfigError(f"value {value} does not fit in {bits} bits")
        digits = f"{value:0{max(1, (bits + 3) // 4)}x}"
        return f"{bits}'h{digits}"

    @classmethod
    def logical_address(cls, value: int) -> str:
        return f"ADDR_WIDTH'({cls.hex_literal(value, 32)})"

    @classmethod
    def physical_address(cls, value: int, raw_address_width: int) -> str:
        return f"PHY_RAW_ADDR_WIDTH'({cls.hex_literal(value, raw_address_width)})"

    @classmethod
    def comment_address(cls, value: int, bits: int) -> str:
        return f"0x{cls.grouped_hex(value, bits)}"
