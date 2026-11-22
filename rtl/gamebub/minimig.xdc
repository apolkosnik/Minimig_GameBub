########################################
# Minimig core constraints (Game Bub)
########################################
# SDRAM interface (rtl/gamebub/gb_sdram_ctrl.sv)
#
# The SDRAM clock is clk_sdram (clk_114 delayed by 0.963 ns, MMCM CLKOUT4)
# inverted, forwarded by an ODDR (ram1/sd_clk_oddr), so the SDRAM takes the
# commands half a clk_114 period plus 0.963 ns after the clk_114 edge that
# changes them. The delay centres both windows: without it the read data
# hold check failed by 0.49 ns and the command setup check by 0.06 ns. The command, chip select,
# address, DQM and write data registers are in the I/O blocks, so they reach
# the pins with about the same delay as the clock. The DQ output enable is
# one register for all 16 pins (the framework has a single direction bit),
# so it stays in the fabric and is timed like the data.
create_generated_clock -name sdram_clk_out -invert -divide_by 1 \
    -source [get_pins -hier -filter {NAME =~ */ram1/sd_clk_oddr/C}] \
    [get_ports sdram_clk]

set sd_out_regs [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */ram1/sd_cs_reg* || NAME =~ */ram1/sd_ras_reg || NAME =~ */ram1/sd_cas_reg || NAME =~ */ram1/sd_we_reg || NAME =~ */ram1/sd_dqm_reg* || NAME =~ */ram1/sd_ba_reg* || NAME =~ */ram1/sd_addr_reg* || NAME =~ */ram1/sd_data_out_reg*)}]
set sd_in_regs  [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ */ram1/sd_in_q_reg*}]
set_property IOB TRUE $sd_out_regs
set_property IOB TRUE $sd_in_regs

# SDRAM timing at CAS latency 3, the slowest common 133 MHz x16 parts
# (IS42S16160J-7, MT48LC16M16A2-75, AS4C16M16SA-7, W9825G6KH-6): input setup
# 1.5 ns, hold 0.8 ns, access time tAC 5.4 ns, output hold tOH 2.5 ns. The
# traces are short; 0.1-0.4 ns each way and 0.2 ns of skew between the
# clock and the other lines are allowed for (as for the 3DO core).
set sdram_out [get_ports {sdram_cs_n[*] sdram_ras_n sdram_cas_n sdram_we_n sdram_ldqm sdram_udqm sdram_bs[*] sdram_a[*] sdram_dq[*]}]
set_output_delay -clock sdram_clk_out -max  1.7 $sdram_out
set_output_delay -clock sdram_clk_out -min -1.0 $sdram_out

# Read data: the word of SDRAM clock edge e is driven from tAC after edge
# e-1 until tOH after edge e. gb_sdram_ctrl takes it (sd_in_q) at the
# clk_114 edge that ends the cycle around edge e: one and a half clk_114
# periods after edge e-1, i.e. a setup multicycle of 2 from the edge that
# launches it. (The hold check then is the next word's launch, at edge e,
# against the same capture edge.)
set_input_delay -clock sdram_clk_out -max 6.2 [get_ports sdram_dq[*]]
set_input_delay -clock sdram_clk_out -min 2.7 [get_ports sdram_dq[*]]
set_multicycle_path -setup 2 -from [get_clocks sdram_clk_out] \
    -to [get_clocks -of_objects [get_pins -hier -filter {NAME =~ */clocks/mmcm/CLKOUT0}]]

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
# cpu_wrapper's own registers (clk_sys, as the CPU's) include the boards'
# base addresses and enables (z3ram_*, z2ram_ena, rtg_*) that memory_router
# decodes into ram1's CPU address.
set mm_chip  [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */minimig/* || NAME =~ *bplpth_reg* || NAME =~ */amiga_clk/* || NAME =~ */cpu_wrapper/*)}]
set_multicycle_path -setup -end 2 -from $mm_chip -to $mm_ram1
set_multicycle_path -hold  -end 1 -from $mm_chip -to $mm_ram1

# configuration registers that only change while the CPU is held
# (Minimig.sdc)
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */minimig/USERIO1/cpu_config_reg* || NAME =~ */minimig/USERIO1/ide_config_reg* || NAME =~ */minimig/USERIO1/bootrom_reg*)}]

# The RTG card's base address: written once, by the autoconfig of the
# board (a 68020 / 68030), before anything uses the board's memory.
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ */cpu_wrapper/rtg_base_reg*}]

# RTG picture (gb_rtg). The registers (clk_sys) reach the HDMI pixel clock
# through two registers each (s_*) and are taken once a frame; a fetch
# request (q_*, clk_av) is held from a line's start until the next and
# taken by clk_114 (m_*) after its toggle went through m_tgl. The line
# buffers and the palette are block RAMs written in one domain and read in
# another.
set_false_path -to [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */rtg/s_*_reg*)}]
set_false_path -to [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */rtg/m_tgl_reg[0]*)}]
# (Vivado moves m_* into the fetch address multiplier's DSP, so the request
# is constrained by the clock it goes to; q_line is also read in clk_av.)
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */rtg/q_line_reg* || NAME =~ */rtg/q_buf_reg* || NAME =~ */rtg/q_base_reg* || NAME =~ */rtg/q_stride_reg* || NAME =~ */rtg/q_hs_reg* || NAME =~ */rtg/q_bpp_reg*)}] \
    -to [get_clocks -of_objects [get_pins -hier -filter {NAME =~ */clocks/mmcm/CLKOUT0}]]

########################################
# The picture's frames (gb_fb): the SRAM
########################################
# Every SRAM pin comes from a register in its I/O block and WE from an ODDR,
# so the pins change together (as in the Game Bub 3DO core, whose SRAM
# controller found on the board that placement-dependent fabric delays
# between them corrupted writes). The read data goes into I/O block
# registers. The data bus direction is one fabric register for all 16 pins
# (the framework has a single direction bit); the bus only turns around
# with an idle clock in between.
set_property IOB TRUE [get_cells -hier -filter {(NAME =~ */fb/o_addr_reg* || NAME =~ */fb/o_data_reg* || NAME =~ */fb/o_mask_reg* || NAME =~ */fb/o_oe_n_reg* || NAME =~ */fb/i_data_reg*) && IS_SEQUENTIAL}]
# The SRAM is asynchronous. gb_fb takes read data three clk_114 clocks after
# the edge that puts the address out, and the next address goes out at that
# edge. Read data: the address's clock-to-pad delay (at most 5 ns), the
# traces (0.5 ns each way) and a 10 ns part's access time; it holds for the
# address's minimum clock-to-pad delay (1.5 ns) plus the part's output hold
# (2.5 ns) after the next address goes out.
set fb_clk_114 [get_clocks -of_objects [get_pins -hier -filter {NAME =~ */clocks/mmcm/CLKOUT0}]]
set_input_delay -clock $fb_clk_114 -max 16.0 [get_ports sram_io[*]]
set_input_delay -clock $fb_clk_114 -min  4.0 [get_ports sram_io[*]]
set_multicycle_path -setup 3 -from [get_ports sram_io[*]]
set_multicycle_path -hold 2 -from [get_ports sram_io[*]]

# gb_fb between its clocks. The screen's request (q_*, clk_av) is held from
# a scan line's start to the next and taken by clk_114 after its toggle went
# through r_ts; `fit` (clk_sys) changes between frames and goes through two
# registers to clk_av; the RTG board's enable likewise (rtg_on_av). The line
# buffers are block RAM written in clk_114 and read in clk_av.
set_false_path -to [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */fb/r_ts_reg[0]* || NAME =~ */fb/fit_s_reg[0]* || NAME =~ */rtg_on_av_reg[0]*)}]
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */fb/q_new_reg* || NAME =~ */fb/q_hdmi_reg* || NAME =~ */fb/q_frame_reg* || NAME =~ */fb/q_need_reg*)}] \
    -to $fb_clk_114
