# Manual environment template for Bash. The dev container sets these itself.
# From the repository root, copy this file to MySetEnv.sh, edit it, then run:
#   source Processor/Tools/SetEnv/MySetEnv.sh
# MySetEnv.sh is ignored by Git. Makefiles do not source it automatically.

# Make infers RSD_ROOT from the checkout and exports it to child processes.

# Required for the basic test programs and benchmarks.
# These defaults match Ubuntu's RISC-V GCC and the dev container.
export RSD_GCC_PATH=/usr/bin

# RISC-V compiler executable prefix.
export RSD_GCC_PREFIX=riscv64-unknown-elf-

# Optional: omit this to use verilator from PATH.
# export RSD_VERILATOR_BIN=/usr/local/bin/verilator

# Optional EDA tools: enable only the tools you use.
# Set up their runtime dependencies and licenses using your site's environment.
# ModelSim/Questa: directory containing vlog, vlib and vsim.
# export RSD_QUESTASIM_PATH=/opt/questa/bin

# Vivado/XSim: directory containing vivado, xvlog, xelab and xsim.
# export RSD_VIVADO_BIN=/opt/Xilinx/Vivado/2019.2/bin

# Optional Synplify command override; otherwise use PATH.
# export SYNPLIFY=/opt/synplify/bin/synplify_premier_dp

# Optional VCS command override; otherwise use PATH.
# export VCS=/opt/vcs/bin/vcs

# Optional: Design Compiler (legacy flow).
# export RSD_DC_SHELL_BIN=/opt/synopsys/bin/dc_shell

# Optional: working directory for Zynq PS Linux image builds (legacy flow).
# export RSD_ARM_LINUX="$HOME/work/rsd-arm-linux"
