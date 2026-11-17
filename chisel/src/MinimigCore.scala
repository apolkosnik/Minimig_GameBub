import chisel3._
import net.gamebub.framework.Core
import net.gamebub.framework.interface._

/**
 * Minimig (Amiga 500/600/1200) for the Game Bub.
 *
 * The core itself is SystemVerilog/VHDL (rtl/); this class only declares the
 * framework interfaces and binds them to the `minimig_gamebub` module.
 *
 * Clocks: one MMCM, 50 MHz * 54.5 / 3 = 908.33 MHz VCO
 *   /8  = 113.54 MHz  SDRAM controller (4 x Amiga clock)
 *   /32 =  28.385 MHz Amiga clock (PAL 28.375 MHz +0.04 %), system clock
 *   /5  = 181.67 MHz  host SPI
 *   /N  = display clock (N chosen from the display's range)
 */
class MinimigCore extends Module with Core {
  val mmcmVcoHz: Double = 50_000_000.0 * 54.5 / 3.0

  val framePeriod = 1.0 / 50.0  // PAL
  val (displayClockMin, displayClockMax) = ClocksV0.getClockDisplayHz(framePeriod)
  val displayDivider = math.floor(mmcmVcoHz / displayClockMin).toInt
  val displayClock = (mmcmVcoHz / displayDivider).toInt
  require(displayDivider >= 1 && displayDivider <= 128, s"display divider $displayDivider out of range")
  require(displayClock <= displayClockMax, s"display clock $displayClock above $displayClockMax")

  val io = IO(new Bundle {
    val clocks = new ClocksV0(
      clockSystemHz = (mmcmVcoHz / 32).toInt,
      clockDisplayHz = displayClock,
      clockSpiHz = (mmcmVcoHz / 5).toInt,
    )
    val video = new VideoV0(
      // 720 high resolution pixels (the standard window and 40 either side:
      // overscan), shown one to one across the panel and fitted across
      // HDMI's 1280; down, the first 240 lines doubled or all 256 fitted to
      // the screen's 480 (patches/framework: independentScale, fit). Two
      // frame buffers of 720 x 256 fit the block RAM at 9 bits per pixel: a
      // pixel is the index of its colour in a palette the core fills
      // (paletteBits).
      videoWidth = 720,
      videoHeight = 256,
      colorDepthR = 3,
      colorDepthG = 3,
      colorDepthB = 3,
      framePeriod = framePeriod,
      independentScale = true,
      paletteBits = 9,
      // RTG: the board's picture (second SDRAM chip) on HDMI
      // (patches/framework 0003)
      externalPicture = true,
    )
    val audio = new AudioV0()
    val host = new HostV0()
    val input = new InputExtendedV0(numSlots = 2)
    val sdram = new SdramV0(addressWidth = 13, dataWidth = 16, bankWidth = 2, chips = 2)
  })

  bindExtModule("minimig_gamebub", io, Map(
    "DISPLAY_DIVIDER" -> displayDivider,
  ))
}
