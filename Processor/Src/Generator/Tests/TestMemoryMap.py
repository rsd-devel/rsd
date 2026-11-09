import copy
from pathlib import Path
import sys
import unittest

SRC = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SRC))
from Generator.config import CpuConfig
from Generator.memory_map_renderer import MemoryMapRenderer
from Generator.yaml_utils import ConfigError, load_yaml


class TestMemoryMap(unittest.TestCase):

    def setUp(self):
        self.values = copy.deepcopy(load_yaml(SRC / 'default.yml'))

    def render(self):
        return MemoryMapRenderer(CpuConfig.from_yaml(self.values), SRC / 'default.yml',
                                 SRC / 'Memory/MemoryMapTypes.template.sv').render(
                                     (SRC / 'Memory/MemoryMapTypes.template.sv').read_text())

    def test_address_space_end(self):
        raw_width = self.values['memory_map']['physical_address_width'] - 2
        self.values['memory_map']['regions']['top'] = {
            'type': 'memory', 'logical_base': 0xfffff000,
            'physical_base': (1 << raw_width) - 0x1000,
            'size': 0x1000, 'translation': 'relative',
            'constants': {'logical_prefix': 'LOG_ADDR_TOP', 'physical_prefix': 'PHY_ADDR_TOP'},
        }
        self.render()
        region = CpuConfig.from_yaml(self.values).memory_map.regions[-1]
        self.assertEqual(region.logical_end, 0xffffffff)
        self.assertEqual(region.physical_range[1], (1 << raw_width) - 1)
        self.values['memory_map']['regions']['top']['size'] += 1
        with self.assertRaises(ConfigError):
            self.render()

    def test_adjacent_regions_and_shared_endpoint(self):
        config = CpuConfig.from_yaml(self.values)
        regions = {region.key: region for region in config.memory_map.regions}
        self.assertEqual(regions['ram'].logical_end + 1, regions['uncachable'].logical_base)
        self.values['memory_map']['regions']['uncachable']['logical_base'] = regions['ram'].logical_end
        with self.assertRaisesRegex(ConfigError, 'overlap'):
            self.render()

    def test_single_byte_region(self):
        config = CpuConfig.from_yaml(self.values)
        serial = next(region for region in config.memory_map.regions if region.key == 'serial')
        self.assertEqual(serial.logical_base, serial.logical_end)
        self.assertEqual(serial.physical_range[0], serial.physical_range[1])

    def test_checked_in_output(self):
        self.assertEqual(self.render(), (SRC / 'Memory/MemoryMapTypes.sv').read_text())


if __name__ == '__main__':
    unittest.main()
