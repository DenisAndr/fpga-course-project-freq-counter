# Крок 6: системна симуляція з РЕАЛЬНИМ .elf (програма freq_main.c на MicroBlaze).
# Запуск з кореня репозиторію (після build_system.tcl і build_vitis.py):
#   vivado -mode batch -source scripts/sim_system.tcl
# Потім проєкт vivado/freq_sys/freq_sys.xpr відкривається в GUI: Run Simulation ->
# Run Behavioral Simulation (тестбенч, ELF і конфіг хвиль уже в sim_1).
set root [file normalize .]
open_project $root/vivado/freq_sys/freq_sys.xpr

file mkdir $root/elf
file copy -force $root/vitis/app_component/build/app_component.elf $root/elf/freq_main.elf

# ---- sim_1: тестбенч + ELF, пов'язаний з MicroBlaze (Associate ELF Files) ----
set old [get_files -all -quiet -of_objects [get_filesets sim_1]]
if {[llength $old] > 0} { remove_files -fileset sim_1 $old }
import_files -fileset sim_1 -norecurse $root/tb/tb_system.v
import_files -fileset sim_1 -norecurse $root/elf/freq_main.elf
set_property top tb_system [get_filesets sim_1]

set elf_obj [get_files -all -of_objects [get_filesets sim_1] -filter {NAME =~ "*freq_main.elf"}]
set_property SCOPED_TO_REF   design_1       $elf_obj
set_property SCOPED_TO_CELLS {microblaze_0} $elf_obj

update_compile_order -fileset sim_1
launch_simulation

# ---- хвилі: сигнал, транзакції AXI4-Lite (групи "запис" і "читання"), стан IP ----
set ip /tb_system/dut/design_1_i/freq_counter_0
add_wave /tb_system/sys_clk /tb_system/sig_in
set gw [add_wave_group {AXI4-Lite WRITE (AW, W, B)}]
foreach n {awvalid awready awaddr wvalid wready wdata bvalid bready} { add_wave -into $gw $ip/s_axi_$n }
set gr [add_wave_group {AXI4-Lite READ (AR, R)}]
foreach n {arvalid arready araddr rvalid rready rdata} { add_wave -into $gr $ip/s_axi_$n }
set gs [add_wave_group {Frequency counter state}]
foreach n {window win_cnt edge_cnt count} { add_wave -into $gs -radix unsigned $ip/inst/$n }
foreach n {busy status} { add_wave -into $gs $ip/inst/$n }
run all
save_wave_config $root/freq_system.wcfg
close_sim

# ---- налаштування для GUI: конфіг хвиль у sim_1, прогін до $finish ----
import_files -fileset sim_1 -norecurse $root/freq_system.wcfg
set wcfg [get_files -of_objects [get_filesets sim_1] -filter {NAME =~ "*freq_system.wcfg"}]
set_property -name xsim.view -value $wcfg -objects [get_filesets sim_1]
set_property -name xsim.simulate.runtime -value all -objects [get_filesets sim_1]
close_project
puts "=== SIM DONE ==="
