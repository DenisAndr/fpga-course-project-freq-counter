# Крок 4: упакувати freq_counter в IP (Package IP) і покласти його в локальний репозиторій IP.
# Запуск з кореня репозиторію:  vivado -mode batch -source scripts/package_ip.tcl
set root [file normalize .]

create_project freq_ip $root/vivado/freq_ip -part xc7z020clg400-1 -force
add_files -norecurse $root/rtl/freq_counter.v
set_property top freq_counter [current_fileset]
update_compile_order -fileset sources_1

# Package IP: файли копіюються в ip_repo/freq_counter
ipx::package_project -root_dir $root/ip_repo/freq_counter \
    -vendor student.local -library user -taxonomy {/UserIP} -import_files -force

set core [ipx::current_core]
set_property display_name {Frequency Counter} $core
set_property description  {Frequency counter: counts rising edges of sig_in in a window set over AXI4-Lite} $core

# Інтерфейси, які Vivado розпізнав за іменами портів
foreach bi [ipx::get_bus_interfaces -of_objects $core] {
    puts "BUSIF: [get_property name $bi]  [get_property abstraction_type_vlnv $bi]  mode=[get_property interface_mode $bi]"
}
puts "MEMMAPS: [ipx::get_memory_maps -of_objects $core]"

# Карта адрес: один блок регістрів (4 регістри вміщаються в мінімальні 4 КБ)
if {[llength [ipx::get_memory_maps -of_objects $core]] == 0} {
    ipx::add_memory_map s_axi $core
    set_property slave_memory_map_ref s_axi [ipx::get_bus_interfaces s_axi -of_objects $core]
    set mm [ipx::get_memory_maps s_axi -of_objects $core]
    ipx::add_address_block reg0 $mm
}
set ab [ipx::get_address_blocks -of_objects [ipx::get_memory_maps s_axi -of_objects $core]]
set_property range 4096 $ab
puts "ADDRBLOCK: [get_property name $ab] range=[get_property range $ab] usage=[get_property usage $ab]"

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

# Перевірка: репозиторій додається в IP Catalog, IP знаходиться
set_property ip_repo_paths $root/ip_repo [current_project]
update_ip_catalog
set found [get_ipdefs -filter {NAME == freq_counter}]
puts "IPCATALOG: $found"
puts "=== DONE: package_ip ==="
close_project
