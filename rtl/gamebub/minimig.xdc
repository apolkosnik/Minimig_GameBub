########################################
# Minimig core constraints (Game Bub)
########################################
# SDRAM interface (rtl/minimig/sdram_ctrl.sv, the MiSTer Minimig controller)
#
# The controller runs on clk_114 (MMCM CLKOUT0, 113.54 MHz) and drives every
# SDRAM pin from a clk_114 register, the SDRAM clock included: sd_clk is
# sdram_state[0], so the SDRAM runs at 56.8 MHz and its rising edge leaves
# the FPGA at a clk_114 edge, like the other outputs. The command, address,
# DQM and write data registers only change at the clk_114 edges at which the
# SDRAM clock falls (sim/tb/sim_main.cpp checks this on every edge of the
# full-system simulation: "SDRAM pins"), so at the pins they are stable for
# a whole clk_114 period (8.8 ns) before and after each rising SDRAM clock
# edge, less the skew between I/O block registers: far more than the 1.5 ns
# setup and 0.8 ns hold of the SDRAM.
#
# Read data is taken by an I/O block register at the clk_114 edge at which
# the SDRAM clock rises, one SDRAM cycle after the edge that launched it
# (CAS latency 2 as the controller programs it): the word is valid at the pin
# from about tAC (6 ns) after the previous rising edge at the SDRAM until
# tOH (2.5 ns) after this one, which leaves several ns on both sides of the
# I/O block register's sampling point (the clock's insertion delay less the
# input buffer's delay).
#
# Both of these hold only with the registers in the I/O blocks, which fixes
# their delays to the pins, so they are placed there and the paths between
# them and the pins are not timed against a clock.
set sd_out_regs [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */ram1/sd_clk_reg || NAME =~ */ram1/sd_ras_reg || NAME =~ */ram1/sd_cas_reg || NAME =~ */ram1/sd_we_reg || NAME =~ */ram1/sd_dqm_reg* || NAME =~ */ram1/sd_ba_reg* || NAME =~ */ram1/sd_addr_reg* || NAME =~ */ram1/sd_data_out_reg*)}]
set sd_in_regs  [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ */ram1/sdata_reg_reg*}]
set_property IOB TRUE $sd_out_regs
set_property IOB TRUE $sd_in_regs
set_false_path -from $sd_out_regs -to [get_ports {sdram_clk sdram_ras_n sdram_cas_n sdram_we_n sdram_ldqm sdram_udqm sdram_bs[*] sdram_a[*] sdram_dq[*]}]
set_false_path -from [get_ports {sdram_dq[*]}] -to $sd_in_regs

# The data output enable is one register for all 16 DQ pins (the framework
# has a single direction bit), so it cannot be in the I/O blocks. It changes
# at falling SDRAM clock edges too; it must reach the pins before the next
# rising edge less the SDRAM's input setup time (8.8 - 1.5 ns).
set_max_delay -datapath_only 6.5 -from [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ */ram1/sd_data_oe_reg}] -to [get_ports {sdram_dq[*]}]

########################################
# clk_sys (28 MHz) -> clk_114 (sdram_ctrl), from the MiSTer core's
# Minimig.sdc
########################################
# sdram_ctrl takes the chipset's and the CPU's requests two clk_114 cycles
# after the clk_sys edge that launches them: it detects the 7 MHz phase
# (c_7m, ~old_7m & c_7m) one clk_114 edge after it changes and starts the
# slot at the next. Minimig.sdc gives these paths a setup multicycle of 2
# (and a hold of 1) for the same reason; without it Vivado times them in one
# clk_114 period (Agnus's beamcon0 decode into the slot's address, the
# TG68K's micro_state into the write buffer).
# (Agnus's bitplane pointer table is a LUT RAM that the synthesised netlist
# names bpd1/bplpth_reg*, outside the minimig hierarchy.)
set mm_ram1  [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */ram1/* || NAME =~ */extModule/ram_cs_reg)}]
set mm_chip  [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */minimig/* || NAME =~ *bplpth_reg* || NAME =~ */amiga_clk/* || NAME =~ */cpu_wrapper/cpu_inst*)}]
set_multicycle_path -setup -end 2 -from $mm_chip -to $mm_ram1
set_multicycle_path -hold  -end 1 -from $mm_chip -to $mm_ram1

# configuration registers that only change while the CPU is held
# (Minimig.sdc)
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */minimig/USERIO1/cpu_config_reg* || NAME =~ */minimig/USERIO1/ide_config_reg* || NAME =~ */minimig/USERIO1/bootrom_reg*)}]

# The RTG card's base address: RTG is only offered with a Zorro III CPU,
# which this core does not build (cpu_wrapper z3cpu is 0), so it never
# changes after reset.
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ */cpu_wrapper/rtg_base_reg*}]
