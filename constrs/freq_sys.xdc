# Обмеження для аналізу часу (крок 7). Плата не потрібна: піни не призначаються.
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]

# sig_in -- зовнішній асинхронний сигнал, він іде лише у 2-ступеневий синхронізатор,
# тому шлях від порту не аналізується; reset проходить через proc_sys_reset.
set_false_path -from [get_ports sig_in]
set_false_path -from [get_ports reset]
