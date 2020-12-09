:: Copy SetEnv.bat, edit the contents, and run it.
::
:: * If environmental variables are not applied, you should reboot your machine.
:: * Do not use backslash "\" in paths you specified. You should use slash "/".
::
:: * If you run RTL simulation, you should set RSD_ROOT and RSD_CYGWIN_PATH. 
::   If you use Modelsim/QuestaSim, you should set RSD_QUESTASIM_PATH in addition  
::   to the above.



:: Specify the root directory where you checked out RSD.
setx RSD_ROOT C:/Work/RSD/

:: Specify the path of Cygwin. 
setx RSD_CYGWIN_PATH C:/cygwin/


:: Specify the path of a directory that contains a gcc cross compiler binary for RISC-V. 
setx RSD_GCC_PATH  C:/opt/gcc/riscv/7.1.0/bin
:: Specify the prefix of the file name of the compiler binary.
setx RSD_GCC_PREFIX riscv32-unknown-elf-

:: Specify the binary path of Modelsim or QuestaSim.
setx RSD_QUESTASIM_PATH C:/dev/env/hdl/Mentor/questa_sim64_10.2c/win64/


:: Specify the binary path of Synplify.
setx SYNOPSYS_BIN C:/dev/env/hdl/Synopsys/fpga_I2013091/bin/

:: Specify the path of "dc_shell" for Design Compiler.
setx RSD_DC_SHELL_BIN C:/opt/cad/synopsys/O-2018.06-SP4/bin/dc_shell

:: Specify the path of a "verilator" binary
setx RSD_VERILATOR_BIN verilator


:: Specify the ISE folder in Vivado.
setx RSD_VIVADO E:/Xilinx/Vivado/2019.2/ids_lite/ISE/

:: Specify the path where CORE Generator/ngc2edif/xtclsh exists
setx RSD_VIVADO_BIN E:/Xilinx/Vivado/2019.2/bin

:: Specify the path of modelsim.ini.
:: This file is generated when libraries for Modelsim are compiled in Vivado.
setx RSD_MODELSIM_INI　C:/Work/RSD/modelsim.ini

:: Specify the path of a work directory where download or build ZYNQ PS Linux 
setx RSD_ARM_LINUX C:/Work/rsd-arm-linux


:: Specify the root path of RSD-env, which is a closed repository that contains 
:: external commercial packages/tools for RSD development.
:: Currenttly, this repository is not opened.
:: setx RSD_ENV C:/Work/RSD-env/

pause
