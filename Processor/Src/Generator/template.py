import re
from dataclasses import dataclass

from Generator.yaml_utils import ConfigError


_PLACEHOLDER = re.compile(r"{{\s*([A-Za-z0-9_]+)\s*}}")


@dataclass(frozen=True)
class TemplateContext:
    generated_notice: str
    instruction_reset_vector: str
    pc_goal: str
    narrow_pc_define: str
    pc_width: str
    physical_address_width: str
    memory_map_doc: str
    memory_map_constants: str
    get_memory_map_type_body: str
    to_physical_address_body: str

    def replacements(self) -> tuple[tuple[str, str], ...]:
        return (
            ("GENERATED_NOTICE", self.generated_notice),
            ("INSN_RESET_VECTOR", self.instruction_reset_vector),
            ("PC_GOAL", self.pc_goal),
            ("RSD_NARROW_PC_DEFINE", self.narrow_pc_define),
            ("PC_WIDTH", self.pc_width),
            ("PHY_ADDR_WIDTH", self.physical_address_width),
            ("MEMORY_MAP_DOC", self.memory_map_doc),
            ("MEMORY_MAP_CONSTANTS", self.memory_map_constants),
            ("GET_MEMORY_MAP_TYPE_BODY", self.get_memory_map_type_body),
            ("TO_PHY_ADDR_FROM_LOGICAL_BODY", self.to_physical_address_body),
        )

    def render(self, template: str) -> str:
        replacements = dict(self.replacements())
        placeholders = set(_PLACEHOLDER.findall(template))
        missing = placeholders - replacements.keys()
        unused = replacements.keys() - placeholders
        if missing:
            raise ConfigError(
                f"unknown template placeholders: {', '.join(sorted(missing))}"
            )
        if unused:
            raise ConfigError(
                f"template placeholders are missing: {', '.join(sorted(unused))}"
            )
        return _PLACEHOLDER.sub(lambda match: replacements[match.group(1)], template)
