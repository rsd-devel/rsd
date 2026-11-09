import copy
from pathlib import Path
import sys
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SRC))
from Generator.config import CpuConfig, load_config
from Generator.memory_map_renderer import MemoryMapRenderer
from Generator.yaml_utils import ConfigError, load_yaml


class TestMemoryMap(unittest.TestCase):

    def setUp(self):
        self.values = copy.deepcopy(load_yaml(SRC / 'MemoryMap.yml'))

    def render(self):
        return MemoryMapRenderer(CpuConfig.from_yaml(self.values), SRC / 'MemoryMap.yml',
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
        renderer = MemoryMapRenderer(CpuConfig.from_yaml(self.values), SRC / 'MemoryMap.yml',
                                     SRC / 'Memory/MemoryMapTypes.template.sv')
        for name, content in renderer.render_software().items():
            self.assertEqual(content, (SRC / 'Verification/TestCode' / name).read_text())


    def test_required_hardware_constants(self):
        del self.values['memory_map']['regions']['plic']
        with self.assertRaisesRegex(ConfigError, 'plic.*required'):
            self.render()

    def test_required_register(self):
        del self.values['memory_map']['regions']['plic']['registers']['CLAIM_COMPLETE_BASE']
        with self.assertRaisesRegex(ConfigError, 'CLAIM_COMPLETE_BASE.*required'):
            self.render()

    def test_required_prefix(self):
        self.values['memory_map']['regions']['serial']['constants']['logical_prefix'] = 'UART'
        with self.assertRaisesRegex(ConfigError, 'must be LOG_ADDR_SERIAL'):
            self.render()

    def test_narrow_pc(self):
        self.values['memory_map']['pc'] = {'narrow': True, 'width': 2}
        with self.assertRaisesRegex(ConfigError, 'narrow PC'):
            self.render()
        # Include the uncachable memory region, not just the reset vector.
        self.values['memory_map']['pc']['width'] = 20
        self.render()

    def test_reset_vector(self):
        for address in (-4, 0x1002, 0x40002000, 0x100000000):
            with self.subTest(address=address):
                self.values['INSN_RESET_VECTOR'] = address
                with self.assertRaises(ConfigError):
                    self.render()

    def test_unknown_setting(self):
        self.values['memory_map']['regions']['ram']['uncachble'] = True
        with self.assertRaisesRegex(ConfigError, 'unknown keys: uncachble'):
            self.render()

    def test_duplicate_setting(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.yml'
            path.write_text('memory_map: {}\nmemory_map: {}\n')
            with self.assertRaisesRegex(ConfigError, 'duplicate YAML key'):
                load_config(path)

    def test_overlap(self):
        self.values['memory_map']['regions']['ram']['logical_base'] = 0x1000
        with self.assertRaises(ConfigError):
            self.render()


    def test_software_addresses_follow_configuration(self):
        self.values['memory_map']['regions']['ram']['logical_base'] = 0x90000000
        self.values['PC_GOAL'] = 0x90001004
        config = CpuConfig.from_yaml(self.values)
        renderer = MemoryMapRenderer(config, SRC / 'MemoryMap.yml',
                                     SRC / 'Memory/MemoryMapTypes.template.sv')
        values = renderer.software_constants()
        self.assertEqual(values['RSD_RAM_BASE'], 0x90000000)
        self.assertEqual(values['RSD_RAM_END'], 0x9003ffff)
        self.assertEqual(values['RSD_RAM_PHYSICAL_BASE'], 0x10000)
        self.assertEqual(values['RSD_CLINT_TIMER_LOW'], 0x40017ff8)


if __name__ == '__main__':
    unittest.main()
