##[

  Video Ppu
  ===========================

  160x144

  Memory map
  ----------

  0xff40  LCDC LCD Control Register
  0xff47-0xff49  Monochrome palettes - Non CGB mode only
    0xff47  BGP  - BG Palette (R/W)
    0xff48  OBP0 - Object Palette 0 (R/W)
    0xff49  OBP1 - Object Palette 1 (R/W)
  
  0x8000-0x9fff  VRAM
    0x8000-0x97ff  Tile Data
      0x8000-0x87ff  Block 0
      0x8800-0x8fff  Block 1
      0x9000-0x97ff  Block 2
    0x9800-0x9bff  BG Map 0
    0x9c00-0x9fff  BG Map 1
  0xfe00-0xfe9f  OAM

  Single line of pixels (fixed 456 cycles)

              2222 3333333
    Scan Line  ----------->
              000000000000
    H Blank    <-----------

    Mode 2  80 cycles (2 cycles per entry in OAM)
    Mode 3  Variable length (168 to 291)
    Mode 0  Variable length, whatever it takes to reach 456 cycles
    Mode 1  456 * 10 = 4560 cycles
  
  Dot frequency
    4194304
  
  Entire refresh
    (Search OAM + Transfer data + H-Blank) * 144 + V-Blank
    456 * 144 + 4560 = 70224

  * `https://gbdev.io/pandocs/#video-display`_
  * `https://nnarain.github.io/2016/09/09/Gameboy-LCD-Controller.html`_
  * `https://www.reddit.com/r/EmuDev/comments/8uahbc/dmg_bgb_lcd_timings_and_cnt/e1iooum/`_

]##
import
  gb/common/util, mem, interrupt



const
  Width* = 160
  Height* = 144

  VramStartAddress* = 0x8000
  OamStartAddress* = 0xfe00

  MapAddress = [ 0x9800, 0x9C00 ]
  WindowAddress = [ 0x9800'u16, 0x9C00 ]
  MapSize* = 32
  TileAddress = [ 0x8800, 0x8000 ]

type
  PpuGrayShade* = enum
    gsWhite = 0
    gsLightGray = 1
    gsDarkGray = 2
    gsBlack = 3
  
  PpuMode = enum
    mHBlank = 0
    mVBlank = 1
    mSearchingOam = 2
    mDataTransfer = 3

  PpuIoState* {.bycopy.} = tuple
    lcdc:     uint8   ## 0xff40  The main LCD control register.
                      ##   bit 7 - LCD Ppu enable flag
                      ##   bit 6 - Window background map selection. (0=0x9800-0x9bff, 1=0x9c00-0x9fff)
                      ##   bit 5 - Window enable flag
                      ##   bit 4 - BG and Window tile addressing mode. (0=0x8800-0x97ff, 1=0x8000-0x8fff)
                      ##   bit 3 - BG map selection, similar to _bit 6_. (0=0x9800-0x9bff, 1=0x9c00-0x9fff)
                      ##   bit 2 - OBJ size. 0: 8x8, 1: 8x16
                      ##   bit 1 - OBJ Ppu enable flag
                      ##   bit 0 - BG/Window Ppu/Priority
                      ##           When Bit 0 is cleared, both background and window become blank (white), and
                      ##           the Window Ppu Bit is ignored in that case. Only Sprites may still be displayed
                      ##           (if enabled in Bit 1).
    stat:     uint8   ## 0xff41  LCDC Status (R/W)
                      ##   bit 6   - LYC=LY Coincidence Interrupt (R/W)
                      ##   bit 5   - Mode 2 OAM Interrupt (R/W)
                      ##   bit 4   - Mode 1 V-Blank Interrupt (R/W)
                      ##   bit 3   - Mode 0 H-Blank Interrupt (R/W)
                      ##   bit 2   - Coincidence Flag (0: LYC != LY, 1: LYC = LY) (R)
                      ##   bit 1-0 - Mode Flag (see _PpuMode_) (R)
                      ##               0: During H-Blank
                      ##               1: During V-Blank
                      ##               2: During Searching OAM
                      ##               3: During Transferring Data to LCD Driver
    scy, scx: uint8   ## 0xff42
    ly:       uint8   ## 0xff44  Y-Coordinate (R)
                      ##   The LY indicates the vertical line to which the present data is transferred to the LCD Driver.
                      ##   The LY can take on any value between 0 through 153. The values between 144 and 153 indicate
                      ##   the V-Blank period.
    lyc:      uint8   ## 0xff45  LY Compare (R/W)
                      ##   The Gameboy permanently compares the value of the LYC and LY registers. When both values are
                      ##   identical, the coincident bit in the STAT register becomes set, and (if enabled) a STAT interrupt
                      ##   is requested.
    dma:      uint8   ## 0xff46
    bgp:      uint8   ## 0xff47  BG Palette Data (R/W) [DMG Only]
                      ##   Color number _PpuGrayShades_ translation for BG and Window tiles.
                      ##     bit 7-6 - _PpuGrayShades_ for color number 3
                      ##     bit 5-4 - _PpuGrayShades_ for color number 2
                      ##     bit 3-2 - _PpuGrayShades_ for color number 1
                      ##     bit 1-0 - _PpuGrayShades_ for color number 0
    obp:      array[2, uint8]
                      ## 0xff48  Object Palette Data (R/W) [DMG Only]
                      ##   Color number _PpuGrayShades_ translation sprite palette.
                      ##   Works exactly as _bgp_, except color number 0 is transparent.
    wy, wx:   uint8   ## 0xff4a
    unk0:     array[4, uint8]
                      ## 0xff4c

  PpuSpriteAttribute {.bycopy.} = tuple
    y, x:  uint8      ## Specifies the sprite position (x - 8, y - 16)
    tile:  uint8      ## Specifies the tile number (0x00..0xff) from the memory at 0x8000-0x8fff
    flags: uint8      ## Attributes
                      ##   bit 7   - OBJ-to-BG Priority (0=OBJ Above BG, 1=OBJ Behind BG color 1-3)
                      ##             (Used for both BG and Window. BG color 0 is always behind OBJ)
                      ##   bit 6   - Y flip (0=Normal, 1=Vertically mirrored)
                      ##   bit 5   - X flip (0=Normal, 1=Horizontally mirrored)
                      ##   bit 4   - Palette number (0=OBP0, 1=OBP1) [DMG Only]
                      ##   bit 3   - Tile VRAM-Bank (0=Bank 0, 1=Bank 1) [CGB Only]
                      ##   bit 2-0 - Palette number (OBP0-7) [CGB Only]
  
  PpuVram = array[8192, uint8]
  
  PpuOam = array[40, PpuSpriteAttribute]

  PpuState* = tuple
    io: PpuIoState
    vram: PpuVram
    oam: PpuOam
    timer: range[0..456]
    stateIR: bool
    dma: uint16
    currentWindowY: int

  Ppu* = ref object
    state*: PpuState
    buffer*: array[Height, array[Width, PpuGrayShade]]
    mcu: Mcu


func isEnabled(self: PpuIoState): bool =
  self.lcdc.testBit(7)

func windowMapAddress(self: PpuIoState): MemAddress =
  WindowAddress[self.lcdc.testBit(6).int]

func isWindowEnabled(self: PpuIoState): bool =
  self.lcdc.testBit(5)

func tileAddress(self: PpuIoState): MemAddress =
  TileAddress[self.lcdc.testBit(4).int].MemAddress

func bgMapAddress*(self: PpuIoState): MemAddress =
  MapAddress[self.lcdc.testBit(3).int].MemAddress

func spriteSize(self: PpuIoState): bool =
  self.lcdc.testBit(2)

func isObjEnabled(self: PpuIoState): bool =
  self.lcdc.testBit(1)

func isBgEnabled(self: PpuIoState): bool =
  self.lcdc.testBit(0)


func bgColorShade*(self: PpuIoState, colorNumber: range[0..3]): PpuGrayShade =
  (self.bgp shl (6 - colorNumber*2) shr 6).PpuGrayShade

func shade(gbPalette: uint8, colorNumber: range[0..3]): PpuGrayShade =
  (gbPalette shl (6 - colorNumber*2) shr 6).PpuGrayShade


func mode(self: var PpuIoState): PpuMode =
  (self.stat and 0b00000011).PpuMode

func `mode=`(self: var PpuIoState, mode: PpuMode) =
  self.stat = self.stat and 0b11111100
  self.stat = self.stat or mode.ord.uint8


func palette*(sprite: PpuSpriteAttribute): int =
  getBit(sprite.flags, 4).int

func isXFlipped*(sprite: PpuSpriteAttribute): bool =
  testBit(sprite.flags, 5)

func isYFlipped*(sprite: PpuSpriteAttribute): bool =
  testBit(sprite.flags, 6)

func priority*(sprite: PpuSpriteAttribute): bool =
  getBit(sprite.flags, 7) == 1

func isVisible(sprite: PpuSpriteAttribute): bool =
  not (sprite.x == 0 or sprite.x >= 168'u8 or sprite.y == 0 or sprite.y >= 168'u8)

func tileAddress(sprite: PpuSpriteAttribute, isBig: bool): int =
  var
    tile = sprite.tile.int
  if isBig:
    tile = tile and 0b11111110
  0x8000 + tile*16


func tileAddress*(state: PpuState, tileNum: uint8): int =
  if state.io.tileAddress().int == 0x8000:
    state.io.tileAddress().int + tileNum.int*16
  else:
    0x9000 + (cast[int8](tileNum)).int*16

iterator tileLine(state: PpuState, tileAddress: int, line: int, palette: uint8, start = 0, flipX = false): PpuGrayShade =
  let
    baseAddress = (tileAddress - VramStartAddress) + (line*2)
    b0 = state.vram[baseAddress]
    b1 = state.vram[baseAddress + 1]
    (a, b) = if flipX: (start, 7) else: (7 - start, 0)
  for j in count(a, b):
    let
      c = (b1.getBit(j) shl 1) or b0.getBit(j)
    yield palette.shade(c)

iterator mapLine*(state: PpuState, x, y: int, width: int, mapAddress: int): tuple[x: int, shade: PpuGrayShade] =
  let
    tileY = (y div 8).wrap32
    startY = y mod 8
  var
    tileX = x div 8
    startX = x mod 8
  block main:
    var
      col = 0
    while true:
      let
        tile = tileY*MapSize + tileX
        tileNum = state.vram[mapAddress + tile]
        tileAddress = state.tileAddress(tileNum)
      for shade in state.tileLine(tileAddress, startY, state.io.bgp, startX):
        yield (x: col, shade: shade)
        col += 1
        if col == width:
          break main
      tileX = (tileX + 1).wrap32
      startX = 0

iterator objLine*(state: PpuState, x, y: int, width: int): tuple[x: int, shade: PpuGrayShade, priority: bool] =
  var
    usedColumns: array[MapSize*8, bool]
  for sprite in state.oam:
    if not sprite.isVisible:
      continue

    let
      sx = sprite.x.int - 8
      sy = sprite.y.int - 16
      height = if state.io.spriteSize: 16 else: 8
    if not(y in sy ..< sy+height)or sx+8 < x or sx >= x+width:
      continue

    let
      f = max(x, sx)
      t = min(x+width, sx+8)
      tileAddress = sprite.tileAddress(state.io.spriteSize)
    var
      line = height - 1 - (sy - y + (height - 1))
    if sprite.isYFlipped: line = height - 1 - line
    var i = f
    for shade in state.tileLine(tileAddress, line, state.io.obp[sprite.palette], f - sx, sprite.isXFlipped):
      if not usedColumns[sprite.x.int]:
        yield (x: i, shade: shade, priority: sprite.priority)
      i += 1
      if i == t:
        break
    
    usedColumns[sprite.x.int] = true

proc transferStart(self: Ppu) =
  let
    y = self.state.io.ly.int
  self.state.io.mode = mDataTransfer

  if self.state.io.isBgEnabled():
    for x, shade in self.state.mapLine(self.state.io.scx.int, self.state.io.scy.int + y, Width, self.state.io.bgMapAddress().int - VramStartAddress):
      self.buffer[y][x] = shade

  if self.state.io.isWindowEnabled() and self.state.io.wx.int <= 166 and self.state.io.wy.int <= 143:
    let
      wx = self.state.io.wx.int - 7
    if y >= self.state.io.wy.int:
      for x, shade in self.state.mapLine(0, self.state.currentWindowY, (Width - wx), self.state.io.windowMapAddress().int - VramStartAddress):
        self.buffer[y][wx + x] = shade
      self.state.currentWindowY += 1

  if self.state.io.isObjEnabled():
    for x, shade, priority in self.state.objLine(0, y, Width):
      if (not priority or self.buffer[y][x] == gsWhite) and shade != gsWhite:
        self.buffer[y][x] = shade

proc nextLine(self: Ppu) =
  self.state.io.ly += 1
  self.state.timer = 0
  self.state.io.stat.toggleBit(2, self.state.io.ly == self.state.io.lyc)

proc handleInterrupt(self: Ppu) =
  let
    mode = self.state.io.mode
    stat = ((self.state.io.ly == self.state.io.lyc) and testBit(self.state.io.stat, 6)) or
      (mode == mHBlank and testBit(self.state.io.stat, 3)) or
      (mode == mSearchingOam and testBit(self.state.io.stat, 5)) or
      (mode == mVBlank and (testBit(self.state.io.stat, 4) or testBit(self.state.io.stat, 5)))
  if not self.state.stateIR and stat:
    self.mcu.raiseInterrupt(iLcdStat)
  self.state.stateIR = stat

proc dmaTransfer(self: Ppu) =
  if (self.state.dma and 0x00ff) <= 0x009f:
    self.mcu[(OamStartAddress.uint16 + (self.state.dma and 0x00ff)).MemAddress] = self.mcu[self.state.dma]
    self.state.dma += 1

proc step*(self: Ppu): bool {.discardable.} =
  if not self.state.io.isEnabled:
    return false

  self.state.timer += 1
  if self.state.timer >= 456:
    self.nextLine()

  case self.state.io.ly
  of 0..(Height-1):
    case self.state.timer
    of 0..79:
      # mSearchingOam
      self.state.io.mode = mSearchingOam
    of 80:
      # mDataTransfer: start
      self.transferStart()
    of 248:
      # mHBlank
      self.state.io.mode = mHBlank
    else:
      discard
  of 144:
    # mVBlank: start
    self.state.io.mode = mVBlank
    self.mcu.raiseInterrupt(iVBlank)
    self.state.currentWindowY = 0
  of 154:
    # mVBlank: end
    self.state.io.ly = 0
    result = true
  else:
    discard

  self.handleInterrupt()
  self.dmaTransfer()


proc setupMemHandler*(mcu: Mcu, self: Ppu) =
  let
    ioHandler = createHandlerFor(msLcdIo, addr self.state.io)
    lcdHandler = MemHandler(
      read: proc(address: MemAddress): uint8 =
        if address == 0xff46:
          0'u8
        else:
          ioHandler.read(address),
      write: proc(address: MemAddress, value: uint8) =
        if address == 0xff46:
          self.state.dma = value.uint16 shl 8
        else:
          ioHandler.write(address, value)
    )
  mcu.setHandler(msLcdIo, lcdHandler)
  mcu.setHandler(msVRam, addr self.state.vram)
  mcu.setHandler(msOam, addr self.state.oam)
  self.mcu = mcu

proc newPpu*(mcu: Mcu): Ppu =
  result = Ppu(
    mcu: mcu
  )
  mcu.setupMemHandler(result)