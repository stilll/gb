when defined(profiler):
  import nimprof

import
  imageman,
  gb/gameboy, shell/render


const
  BootRom = ""
  Rom = staticRead("../tests/rom/blargg/cpu_instrs/cpu_instrs.gb")

proc init(): Gameboy =
  result = newGameboy(BootRom)
  result.load(Rom)

proc frame(gameboy: Gameboy, isRunning: var bool): Image[ColorRGBU] =
  try:
    var
      needsRedraw = false
    while not needsRedraw:
      needsRedraw = needsRedraw or gameboy.step()
  except:
    isRunning = false

  result = initPainter(PaletteDefault).renderLcd(gameboy.dmg.ppu)



when defined(wasm):
  include shell/simple/wasm
elif defined(psp):
  include shell/simple/psp
else:
  include shell/simple/pc

main()
