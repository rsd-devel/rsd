// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// This file is used on synthesis using only Vivado (not for flow using synplify).
// This is because Vivado can only recognize header files for files 
// with .vh or .svh extension.
// Hence, SynthesisMacros.sv cannot treat them as header files.
//
`include "../SynthesisMacros.sv"
