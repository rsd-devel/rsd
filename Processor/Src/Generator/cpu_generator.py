#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from Generator.config import load_config
from Generator.memory_map_renderer import MemoryMapRenderer
from Generator.yaml_utils import ConfigError


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate MemoryMapTypes.sv from the RSD source configuration."
    )
    parser.add_argument(
        "--rsd-root",
        required=True,
        type=Path,
        help="RSD repository root",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_root = args.rsd_root / "Processor" / "Src"
    config_path = source_root / "default.yml"
    template_path = source_root / "Memory" / "MemoryMapTypes.template.sv"
    output_path = source_root / "Memory" / "MemoryMapTypes.sv"

    try:
        config = load_config(config_path)
        template = template_path.read_text(encoding="utf-8")
        renderer = MemoryMapRenderer(config, config_path, template_path)
        output_path.write_text(renderer.render(template), encoding="utf-8")
    except (ConfigError, OSError) as exc:
        print(f"cpu_generator.py: error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
