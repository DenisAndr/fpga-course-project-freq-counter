# Кроки 5 і 7: Block Design (MicroBlaze + freq_counter), Validate, адреса, Implementation, звіти, XSA.
# Запуск з кореня репозиторію (після package_ip.tcl):  vivado -mode batch -source scripts/build_system.tcl
set root [file normalize .]
set proj freq_sys

create_project $proj $root/vivado/$proj -part xc7z020clg400-1 -force
set_property ip_repo_paths $root/ip_repo [current_project]
update_ip_catalog
create_bd_design design_1

# ---- MicroBlaze + локальна пам'ять 64 КБ + debug module; зовнішні такт і скидання ----
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze microblaze_0
apply_bd_automation -rule xilinx.com:bd_rule:microblaze \
    -config {axi_intc {0} axi_periph {Enabled} cache {None} clk {New External Port} cores {1} debug_module {Debug Only} ecc {None} local_mem {64KB} preset {None}} \
    [get_bd_cells microblaze_0]

set clk_port [get_bd_ports -filter {TYPE == clk}]
set_property CONFIG.FREQ_HZ 100000000 $clk_port
set_property name sys_clk $clk_port
set clk_port [get_bd_ports sys_clk]

set rst_cell [get_bd_cells -hier -filter {VLNV =~ "xilinx.com:ip:proc_sys_reset:*"}]
create_bd_port -dir I -type rst reset
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports reset]
connect_bd_net [get_bd_ports reset] [get_bd_pins $rst_cell/ext_reset_in]
set aresetn [get_bd_pins $rst_cell/peripheral_aresetn]

# ---- мій IP і SmartConnect між MicroBlaze та IP ----
create_bd_cell -type ip -vlnv student.local:user:freq_counter:1.0 freq_counter_0
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect axi_smc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_smc]

connect_bd_intf_net [get_bd_intf_pins microblaze_0/M_AXI_DP] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI]       [get_bd_intf_pins freq_counter_0/s_axi]

foreach p {axi_smc/aclk freq_counter_0/s_axi_aclk} { connect_bd_net $clk_port [get_bd_pins $p] }
foreach p {axi_smc/aresetn freq_counter_0/s_axi_aresetn} { connect_bd_net $aresetn [get_bd_pins $p] }

# sig_in -- зовнішній порт Block Design (Make External)
make_bd_pins_external -name sig_in [get_bd_pins freq_counter_0/sig_in]

# ---- адреси ----
assign_bd_address
foreach s [get_bd_addr_segs] { puts "SEG: $s  offset=[get_property OFFSET $s] range=[get_property RANGE $s]" }

puts "VALIDATE: [validate_bd_design]"
save_bd_design

# ---- wrapper, обмеження, вихідні продукти ----
make_wrapper -files [get_files design_1.bd] -top
add_files -norecurse [glob $root/vivado/$proj/$proj.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v]
set_property top design_1_wrapper [current_fileset]
add_files -fileset constrs_1 -norecurse $root/constrs/freq_sys.xdc
update_compile_order -fileset sources_1
generate_target all [get_files design_1.bd]

# ---- Implementation (-jobs 4: потрібна для кроку 7 і для експорту XSA) ----
launch_runs impl_1 -jobs 4
wait_on_run impl_1
puts "IMPL STATUS: [get_property STATUS [get_runs impl_1]]"

open_run impl_1
file mkdir $root/docs
report_utilization -file $root/docs/utilization_total.txt
report_utilization -cells [get_cells design_1_i/freq_counter_0] -file $root/docs/utilization_ip.txt
report_timing_summary -file $root/docs/timing_summary.txt
puts "WNS: [get_property SLACK [get_timing_paths -max_paths 1 -setup]]"

write_hw_platform -fixed -force -file $root/freq_sys.xsa
puts "=== DONE: build_system ==="
