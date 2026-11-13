# Vivado batch build for FPGA Geometry Dash on the Nexys A7-100T.
#   vivado -mode batch -source build.tcl
# Produces vivado/gd_nexys.runs/impl_1/vga_top.bit
# (Or do it in the GUI: new RTL project, part xc7a100tcsg324-1, add every file in
#  src/ as a design source and constraints/vga_demo.xdc as the constraint file.)

set root [file dirname [file normalize [info script]]]
create_project gd_nexys $root/vivado -part xc7a100tcsg324-1 -force
add_files [glob $root/src/*.v]
add_files -fileset constrs_1 $root/constraints/vga_demo.xdc
set_property top vga_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_utilization -file $root/vivado/utilization.txt
report_timing_summary -file $root/vivado/timing_summary.txt
puts "Bitstream: $root/vivado/gd_nexys.runs/impl_1/vga_top.bit"
