import copy
from pathlib import Path
import re
import sys
import unittest

PROCESSOR = Path(__file__).resolve().parents[3]
SRC = PROCESSOR / "Src"
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ConfigGenerator import ConfigError, load_toml, render_micro_arch


class TestMicroArch(unittest.TestCase):
    def setUp(self):
        self.values = copy.deepcopy(load_toml(PROCESSOR / "Config/MicroArch.toml"))
        self.template = (SRC / "Config/MicroArchConf.template.sv").read_text()

    def render(self):
        return render_micro_arch(self.values, self.template)

    def test_checked_in_outputs(self):
        for name, content in self.render().items():
            self.assertEqual(content, (SRC / name).read_text(), name)

    def test_changed_parameters_and_derived_widths(self):
        self.values["parameters"].update(commit_width=4, load_queue_entry_num=32,
                                         dcache_way_num=4)
        rtl = self.render()["Config/MicroArchConf.sv"]
        self.assertIn("CONF_COMMIT_WIDTH = 4;", rtl)
        self.assertIn("CONF_LOAD_QUEUE_ENTRY_NUM = 32;", rtl)
        self.assertIn("CONF_DCACHE_WAY_NUM = 4;", rtl)
        self.assertIn("9 - $clog2(CONF_DCACHE_WAY_NUM)", rtl)
        self.assertIn("CONF_DECODE_WIDTH = CONF_FETCH_WIDTH;", rtl)

    def test_simulation_and_synthesis_macros_match(self):
        self.values.pop("overrides", None)
        for fp_enabled in (False, True):
            with self.subTest(fp_enabled=fp_enabled):
                self.values["parameters"].update(enable_fp_pipe=fp_enabled,
                                                int_issue_width=1,
                                                enable_zicfilp=False,
                                                enable_unified_ldst_mem_pipe=True)
                outputs = self.render()
                make = outputs["Makefiles/MicroArch.inc.mk"]
                sv = outputs["Config/MicroArchMacros.svh"]
                make_macros = re.findall(r"\+define\+(\w+)(?:=(\d+))?",
                                        make.splitlines()[1])
                sv_macros = re.findall(r"^`define (\w+)(?: (\d+))?$", sv, re.M)
                self.assertEqual(make_macros, sv_macros)
                self.assertEqual(("RSD_MARCH_FP_PIPE", "") in make_macros, fp_enabled)
                self.assertNotIn("RSD_ENABLE_ZICFILP", make)
                self.assertIn("CONF_INT_ISSUE_WIDTH = 1;", outputs["Config/MicroArchConf.sv"])

    def test_performance_counter_defaults(self):
        outputs = self.render()
        make = outputs["Makefiles/MicroArch.inc.mk"].splitlines()
        self.assertNotIn("RSD_DISABLE_PERFORMANCE_COUNTER", make[1])
        self.assertIn("RSD_DISABLE_PERFORMANCE_COUNTER", make[2])
        self.assertIn("`define RSD_DISABLE_PERFORMANCE_COUNTER", outputs["Config/MicroArchMacros.svh"])

    def test_common_values_and_mode_overrides(self):
        self.values["parameters"]["enable_performance_counter"] = False
        self.values["overrides"] = {
            "simulation": {"int_issue_width": 1, "enable_fp_pipe": False},
            "synthesis": {"enable_performance_counter": True},
        }
        outputs = self.render()
        sim, synth = outputs["Makefiles/MicroArch.inc.mk"].splitlines()[1:]
        self.assertIn("RSD_MARCH_INT_ISSUE_WIDTH=1", sim)
        self.assertNotIn("RSD_MARCH_FP_PIPE", sim)
        self.assertIn("RSD_DISABLE_PERFORMANCE_COUNTER", sim)
        self.assertIn("RSD_MARCH_INT_ISSUE_WIDTH=2", synth)
        self.assertIn("RSD_MARCH_FP_PIPE", synth)
        self.assertNotIn("RSD_DISABLE_PERFORMANCE_COUNTER", synth)
        self.assertNotIn("RSD_DISABLE_PERFORMANCE_COUNTER", outputs["Config/MicroArchMacros.svh"])

    def test_numeric_overrides(self):
        self.values["overrides"]["synthesis"]["load_queue_entry_num"] = 32
        rtl = self.render()["Config/MicroArchConf.sv"]
        self.assertIn("`ifdef RSD_SYNTHESIS\nlocalparam CONF_LOAD_QUEUE_ENTRY_NUM = 32;\n"
                      "`elsif RSD_POST_SYNTHESIS_SIMULATION\nlocalparam CONF_LOAD_QUEUE_ENTRY_NUM = 32;\n"
                      "`else\nlocalparam CONF_LOAD_QUEUE_ENTRY_NUM = 16;\n`endif", rtl)

    def test_invalid_overrides(self):
        for overrides in (
            {"synthessis": {}},
            {"synthesis": {"enable_performace_counter": False}},
            {"simulation": {"enable_performance_counter": 0}},
            {"synthesis": {"commit_width": 1}},
            {"synthesis": {"int_issue_width": 3}},
            {"synthesis": {"enable_fp_pipe": "false"}},
            {"synthesis": None},
            [],
        ):
            with self.subTest(overrides=overrides):
                self.values["overrides"] = overrides
                with self.assertRaises(ConfigError):
                    self.render()

    def test_invalid_values(self):
        cases = (
            ("fetch_width", True),
            ("commit_width", 1),
            ("pscalar_fp_num", 128),
            ("replay_queue_entry_num", 0),
            ("load_queue_entry_num", 17),
            ("icache_way_num", 1),
            ("branch_global_history_bit_width", 12),
            ("dcache_index_bit_width_base", 32),
            ("dcache_index_bit_width_base", 1),
            ("int_issue_width", 3),
            ("enable_fp_pipe", 0),
        )
        for name, value in cases:
            with self.subTest(name=name, value=value):
                values = copy.deepcopy(self.values)
                values["parameters"][name] = value
                with self.assertRaises(ConfigError):
                    render_micro_arch(values, self.template)

    def test_missing_or_unknown_setting(self):
        del self.values["parameters"]["enable_fp_pipe"]
        with self.assertRaisesRegex(ConfigError, "required"):
            self.render()
        self.values["parameters"]["enable_fp_pipe"] = True
        self.values["parameters"]["fetch_widht"] = 2
        with self.assertRaisesRegex(ConfigError, "unknown"):
            self.render()

    def test_template_mismatch(self):
        self.template = self.template.replace("{{ FETCH_WIDTH }}", "{{ FETCH_WIDHT }}")
        with self.assertRaisesRegex(ConfigError, "placeholders"):
            self.render()


if __name__ == "__main__":
    unittest.main()
