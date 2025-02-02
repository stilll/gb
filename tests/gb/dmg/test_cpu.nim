import
  std/[unittest, strformat],
  gb/dmg/[mem, cpu]



template cpuTest(name: untyped, body: untyped) =
  test name:
    var
      mem {.inject.} = newSeq[uint8](8)
      mcu {.inject.} = newMcu(addr mem)
      cpu {.inject.} = newCpu(mcu)
    body
    step(cpu, mcu)
    check cpu.state == oldS
    check mem == oldM


template modState(cpu: SM83, body: untyped): CpuState =
  var
    s {.inject.} = cpu.state
  body
  s

template modMem(mem: seq[uint8], body: untyped): seq[uint8] =
  var
    m {.inject.} = mem
  body
  m

template modMem(mem: seq[uint8]): seq[uint8] =
  mem



suite "unit.dmg.cpu: LR35902 - Misc/control instructions":
  cpuTest "NOP":
    mem[0] = 0x00'u8
    let
      oldS = cpu.modState:
        s.pc += 1
      oldM = mem.modMem
  
  test "STOP":
    skip

  cpuTest "HALT":
    mem[0] = 0x76'u8
    let
      oldS = cpu.modState:
        s.pc += 1
        s.status = { sfHalted }
      oldM = mem.modMem
  
  test "HALT - halted":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0x76'u8
    mem[1] = 0x00'u8
    cpu.step(mcu)
    cpu.step(mcu)
    check cpu.state.pc == 1
  
  test "HALT - resume":
    #[ TODO
    var
      mem = newSeq[uint8](128)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0x76'u8
    mem[1] = 0x00'u8
    cpu.step(mcu)
    cpu.step(mcu)
    cpu.state.ime = 1
    cpu.state.ie = { iJoypad }
    cpu.state.`if` = { iJoypad }
    cpu.step(mcu)
    check cpu.state.status == {}
    check cpu.state.pc == 0x60
    ]#
    skip

  test "DI":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    cpu.state.ime = 1
    mem[0] = 0xf3'u8
    mem[1] = 0x00'u8
    cpu.step(mcu)
    check cpu.state.ime == 1
    cpu.step(mcu)
    check cpu.state.ime == 0

  test "EI":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    cpu.state.ime = 0
    mem[0] = 0xfb'u8
    mem[1] = 0x00'u8
    cpu.step(mcu)
    check cpu.state.ime == 0
    cpu.step(mcu)
    check cpu.state.ime == 1


suite "unit.dmg.cpu: LR35902 - Jumps/calls":
  cpuTest "RET":
    cpu.state.sp = 6
    mem[0] = 0xc9'u8
    mem[7] = 0'u8
    mem[6] = 5'u8
    let
      oldS = cpu.modState:
        s.pc = 5
        s.sp = 8
      oldM = mem.modMem


suite "unit.dmg.cpu: LR35902 - 8bit load/store/move instructions":
  cpuTest "LD B,d8":
    mem[0] = 0x06'u8
    mem[1] = 5'u8
    let
      oldS = cpu.modState:
        s.pc += 2
        s[rB] = 5
      oldM = mem.modMem
  
  cpuTest "LD (3),A":
    mem[0] = 0xea'u8
    mem[1] = 3'u8
    mem[2] = 0'u8
    cpu.state[rA] = 5
    let
      oldS = cpu.modState:
        s.pc += 3
      oldM = mem.modMem:
        m[3] = 5

  cpuTest "LD A,(3)":
    mem[0] = 0xfa'u8
    mem[1] = 3'u8
    mem[2] = 0'u8
    mem[3] = 5
    let
      oldS = cpu.modState:
        s.pc += 3
        s[rA] = 5
      oldM = mem.modMem
  
  const
    Ldr8r8Tests = [
      (0x7f, rA, rA), (0x78, rA, rB), (0x79, rA, rC), (0x7a, rA, rD), (0x7b, rA, rE), (0x7c, rA, rH), (0x7d, rA, rL),
      (0x47, rB, rA), (0x40, rB, rB), (0x41, rB, rC), (0x42, rB, rD), (0x43, rB, rE), (0x44, rB, rH), (0x45, rB, rL),
      (0x4f, rC, rA), (0x48, rC, rB), (0x49, rC, rC), (0x4a, rC, rD), (0x4b, rC, rE), (0x4c, rC, rH), (0x4d, rC, rL),
      (0x57, rD, rA), (0x50, rD, rB), (0x51, rD, rC), (0x52, rD, rD), (0x53, rD, rE), (0x54, rD, rH), (0x55, rD, rL),
      (0x5f, rE, rA), (0x58, rE, rB), (0x59, rE, rC), (0x5a, rE, rD), (0x5b, rE, rE), (0x5c, rE, rH), (0x5d, rE, rL),
      (0x67, rH, rA), (0x60, rH, rB), (0x61, rH, rC), (0x62, rH, rD), (0x63, rH, rE), (0x64, rH, rH), (0x65, rH, rL),
      (0x6f, rL, rA), (0x68, rL, rB), (0x69, rL, rC), (0x6a, rL, rD), (0x6b, rL, rE), (0x6c, rL, rH), (0x6d, rL, rL)
    ]
  for reg in Ldr8r8Tests:
    cpuTest &"LD {reg[1]},{reg[2]}":
      mem[0] = reg[0].uint8
      cpu.state[reg[2]] = 5
      let
        oldS = cpu.modState:
          s.pc += 1
          s[reg[1]] = 5
        oldM = mem.modMem

  for reg in [(0x7e, rA), (0x46, rB), (0x4e, rC), (0x56, rD), (0x5e, rE), (0x66, rH), (0x6e, rL)]:
    cpuTest &"LD {reg[1]},(HL)":
      mem[0] = reg[0].uint8
      mem[3] = 5
      cpu.state[rHL] = 3
      let
        oldS = cpu.modState:
          s.pc += 1
          s[reg[1]] = 5
        oldM = mem.modMem
  
  for reg in [(0x77, rA), (0x70, rB), (0x71, rC), (0x72, rD), (0x73, rE)#[, (0x74, rH), (0x75, rL)]#]:
    cpuTest &"LD (HL),{reg[1]}":
      mem[0] = reg[0].uint8
      cpu.state[reg[1]] = 5
      cpu.state[rHL] = 3
      let
        oldS = cpu.modState:
          s.pc += 1
        oldM = mem.modMem:
          m[3] = 5
  
  for reg in [(0x3e, rA), (0x06, rB), (0x0e, rC), (0x16, rD), (0x1e, rE), (0x26, rH), (0x2e, rL)]:
    cpuTest &"LD {reg[1]},8":
      mem[0] = reg[0].uint8
      mem[1] = 8
      let
        oldS = cpu.modState:
          s.pc += 2
          s[reg[1]] = 8
        oldM = mem.modMem
  
  cpuTest &"LD (HL),8":
    mem[0] = 0x36'u8
    mem[1] = 8
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 2
      oldM = mem.modMem:
        m[3] = 8
  
  for reg in [(0x02, rBC), (0x12, rDE)]:
    cpuTest &"LD ({reg[1]}),A":
      mem[0] = reg[0].uint8
      cpu.state[rA] = 8
      cpu.state[reg[1]] = 3
      let
        oldS = cpu.modState:
          s.pc += 1
        oldM = mem.modMem:
          m[3] = 8
  
  for reg in [(0x0a, rBC), (0x1a, rDE)]:
    cpuTest &"LD A,({reg[1]})":
      mem[0] = reg[0].uint8
      mem[3] = 8
      cpu.state[reg[1]] = 3
      let
        oldS = cpu.modState:
          s.pc += 1
          s[rA] = 8
        oldM = mem.modMem
  
  cpuTest "LD (HL+),A":
    mem[0] = 0x22'u8
    cpu.state[rA] = 8
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 1
        s[rHL] = 4
      oldM = mem.modMem:
        m[3] = 8
  
  cpuTest "LD (HL-),A":
    mem[0] = 0x32'u8
    cpu.state[rA] = 8
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 1
        s[rHL] = 2
      oldM = mem.modMem:
        m[3] = 8
  
  cpuTest "LD A,(HL+)":
    mem[0] = 0x2a'u8
    mem[3] = 8
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 1
        s[rHL] = 4
        s[rA] = 8
      oldM = mem.modMem
  
  cpuTest "LD A,(HL-)":
    mem[0] = 0x3a'u8
    mem[3] = 8
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 1
        s[rHL] = 2
        s[rA] = 8
      oldM = mem.modMem


suite "unit.dmg.cpu: LR35902 - 16bit load/store/move instructions":
  for reg in [(0x01, rBC), (0x11, rDE), (0x21, rHL)]:
    cpuTest &"LD {reg[1]},0x1234":
      mem[0] = reg[0].uint8
      mem[1] = 0x34
      mem[2] = 0x12
      let
        oldS = cpu.modState:
          s.pc += 3
          s[reg[1]] = 0x1234
        oldM = mem.modMem
  
  cpuTest "LD SP,0x1234":
    mem[0] = 0x31
    mem[1] = 0x34
    mem[2] = 0x12
    let
      oldS = cpu.modState:
        s.pc += 3
        s.sp = 0x1234
      oldM = mem.modMem
  
  cpuTest "LD (0x0003),SP":
    mem[0] = 0x08
    mem[1] = 0x03
    mem[2] = 0x00
    cpu.state.sp = 0x1234'u16
    let
      oldS = cpu.modState:
        s.pc += 3
        mem[3] = 0x34
        mem[4] = 0x12
      oldM = mem.modMem
  
  cpuTest "LD SP,HL":
    mem[0] = 0xf9
    cpu.state[rHL] = 0x1234'u16
    let
      oldS = cpu.modState:
        s.pc += 1
        s.sp = 0x1234
      oldM = mem.modMem
  
  cpuTest "LD HL,SP+2 - sp=0x1234":
    mem[0] = 0xf8
    mem[1] = 2
    cpu.state.sp = 0x1234'u16
    let
      oldS = cpu.modState:
        s.pc += 2
        s[rHL] = 0x1236
        s.flags = {}
      oldM = mem.modMem
  
  cpuTest "LD HL,SP+2 - sp=0xffff":
    mem[0] = 0xf8
    mem[1] = 2
    cpu.state.sp = 0xffff'u16
    let
      oldS = cpu.modState:
        s.pc += 2
        s[rHL] = 0x0001'u16
        s.flags = { fCarry, fHalfCarry }
      oldM = mem.modMem
  
  for reg in [(0xc5, rBC), (0xd5, rDE), (0xe5, rHL), (0xf5, rAF)]:
    cpuTest &"PUSH {reg[1]}":
      mem[0] = reg[0].uint8
      cpu.state.sp = 8
      cpu.state[reg[1]] = 0x1234
      let
        oldS = cpu.modState:
          s.pc += 1
          s.sp = 6
        oldM = mem.modMem:
          m[7] = 0x12
          m[6] = 0x34
  
  for reg in [(0xc1, rBC), (0xd1, rDE), (0xe1, rHL)]:
    cpuTest &"POP {reg[1]}":
      mem[0] = reg[0].uint8
      mem[7] = 0x12
      mem[6] = 0x34
      cpu.state.sp = 6
      let
        oldS = cpu.modState:
          s.pc += 1
          s.sp = 8
          s[reg[1]] = 0x1234
        oldM = mem.modMem
  
  cpuTest "POP AF":
    mem[0] = 0xf1
    mem[7] = 0x12
    mem[6] = 0x34
    cpu.state.sp = 6
    let
      oldS = cpu.modState:
        s.pc += 1
        s.sp = 8
        s[rAF] = 0x1230
      oldM = mem.modMem


suite "unit.dmg.cpu: LR35902 - 16bit arithmetic/logical instructions":
  cpuTest "ADD HL,DE":
    mem[0] = 0x19'u8
    cpu.state[rHL] = 1
    cpu.state[rDE] = 2
    let
      oldS = cpu.modState:
        s.pc += 1
        s[rHL] = 3
      oldM = mem.modMem
  
  cpuTest "ADD HL,SP":
    mem[0] = 0x39'u8
    cpu.state[rHL] = 1
    cpu.state.sp = 2
    let
      oldS = cpu.modState:
        s.pc += 1
        s[rHL] = 3
      oldM = mem.modMem


suite "unit.dmg.cpu: LR35902 - 8bit arithmetic/logical instructions":
  cpuTest "DEC r8 - 10":
    mem[0] = 0x05'u8
    cpu.state[rB] = 10
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fAddSub }
        s[rB] = 9
      oldM = mem.modMem
  
  cpuTest "DEC r8 - 0":
    mem[0] = 0x05'u8
    cpu.state[rB] = 0
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fHalfCarry, fAddSub }
        s[rB] = 255
      oldM = mem.modMem
  
  cpuTest "OR r8 - non 0":
    mem[0] = 0xb2'u8
    cpu.state[rA] = 0b00001111
    cpu.state[rD] = 0b10101010
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b10101111
      oldM = mem.modMem
  
  cpuTest "OR r8 - 0":
    mem[0] = 0xb2'u8
    cpu.state[rA] = 0b00000000
    cpu.state[rD] = 0b00000000
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fZero }
        s[rA] = 0b00000000
      oldM = mem.modMem
  
  cpuTest "OR (HL)":
    mem[0] = 0xb6'u8
    mem[1] = 0b10101010'u8
    cpu.state[rA] = 0b00001111
    cpu.state[rHL] = 1
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b10101111
      oldM = mem.modMem
  
  cpuTest "OR A":
    mem[0] = 0xb7'u8
    cpu.state[rA] = 0b00001111
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { }
        s[rA] = 0b00001111
      oldM = mem.modMem
  
  cpuTest "CPL":
    mem[0] = 0x2f'u8
    cpu.state[rA] = 0b10011001
    let
      oldS = cpu.modState:
        s.pc += 1
        s.flags = { fAddSub, fHalfCarry }
        s[rA] = 0b01100110
      oldM = mem.modMem
  
  cpuTest "SUB 8 - a=8":
    mem[0] = 0xd6'u8
    mem[1] = 8
    cpu.state[rA] = 8'u8
    let
      oldS = cpu.modState:
        s.pc += 2
        s.flags = { fZero, fAddSub }
        s[rA] = 0
      oldM = mem.modMem
  
  cpuTest "SUB 8 - a=5":
    mem[0] = 0xd6'u8
    mem[1] = 8
    cpu.state[rA] = 5'u8
    let
      oldS = cpu.modState:
        s.pc += 2
        s.flags = { fAddSub, fCarry, fHalfCarry }
        s[rA] = 0xfd
      oldM = mem.modMem


suite "unit.dmg.cpu: LR35902 - 8bit rotations/shifts and bit instructions":
  cpuTest "RL r8 - c=0 00000000":
    mem[0] = 0xcb
    mem[1] = 0x11
    cpu.state[rC] = 0b00000000
    cpu.state.flags = {}
    let
      oldS = cpu.modState:
        s.pc += 2
        s.flags = { fZero }
      oldM = mem.modMem

  cpuTest "RL r8 - c=0 10000000":
    mem[0] = 0xcb'u8
    mem[1] = 0x11
    cpu.state[rC] = 0b10000000
    cpu.state.flags = {}
    let
      oldS = cpu.modState:
        s.pc += 2
        s.flags = { fZero, fCarry }
        s[rC] = 0b00000000
      oldM = mem.modMem

  cpuTest "RL r8 - c=1 00000100":
    mem[0] = 0xcb'u8
    mem[1] = 0x11
    cpu.state[rC] = 0b00000100
    cpu.state.flags = { fCarry }
    let
      oldS = cpu.modState:
        s.pc += 2
        s.flags = {}
        s[rC] = 0b00001001
      oldM = mem.modMem
  
  for reg in [(rA, 0x37), (rB, 0x30), (rC, 0x31), (rD, 0x32), (rE, 0x33), (rH, 0x34), (rL, 0x35)]:
    cpuTest &"SWAP {reg[0]} - not 0":
      mem[0] = 0xcb'u8
      mem[1] = reg[1].uint8
      cpu.state[reg[0]] = 0b00010111
      let
        oldS = cpu.modState:
          s.pc += 2
          s.flags = {}
          s[reg[0]] = 0b01110001
        oldM = mem.modMem
    
    cpuTest &"SWAP {reg[0]} - 0":
      mem[0] = 0xcb'u8
      mem[1] = reg[1].uint8
      cpu.state[reg[0]] = 0b00000000
      let
        oldS = cpu.modState:
          s.pc += 2
          s.flags = { fZero }
          s[reg[0]] = 0b00000000
        oldM = mem.modMem

  for reg in [(rA, 0x87), (rB, 0x80), (rC, 0x81), (rD, 0x82), (rE, 0x83), (rH, 0x84), (rL, 0x85)]:
    cpuTest &"RES 0,{reg[0]}":
      mem[0] = 0xcb'u8
      mem[1] = reg[1].uint8
      cpu.state[reg[0]] = 0b11111111
      let
        oldS = cpu.modState:
          s.pc += 2
          s[reg[0]] = 0b11111110
        oldM = mem.modMem

  cpuTest &"RES 0,(HL)":
    mem[0] = 0xcb'u8
    mem[1] = 0x86'u8
    mem[3] = 0b11111111
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 2
      oldM = mem.modMem:
        m[3] = 0b11111110
  
  for reg in [(rA, 0xc7), (rB, 0xc0), (rC, 0xc1), (rD, 0xc2), (rE, 0xc3), (rH, 0xc4), (rL, 0xc5)]:
    cpuTest &"SET 0,{reg[0]}":
      mem[0] = 0xcb'u8
      mem[1] = reg[1].uint8
      cpu.state[reg[0]] = 0b00000000
      let
        oldS = cpu.modState:
          s.pc += 2
          s[reg[0]] = 0b00000001
        oldM = mem.modMem

  cpuTest &"SET 0,(HL)":
    mem[0] = 0xcb'u8
    mem[1] = 0xc6'u8
    mem[3] = 0b00000000
    cpu.state[rHL] = 3
    let
      oldS = cpu.modState:
        s.pc += 2
      oldM = mem.modMem:
        m[3] = 0b00000001


suite "unit.dmg.cpu: LR35902 - combined":
  test "set 16bit register":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    cpu.state[rBC] = 0x1234

    check cpu.state[rB] == 0x12
    check cpu.state[rC] == 0x34

  test "PUSH POP":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    mem[0] = 0xc5'u8
    mem[1] = 0xe1'u8
    cpu.state[rBC] = 0x1234
    cpu.state.sp = 7
    let
      oldS = cpu.modState:
        s.pc += 2
        s[rHL] = 0x1234
    var
      oldM = mem.modMem
    oldM[5] = 0x34
    oldM[6] = 0x12
    cpu.step(mcu)
    cpu.step(mcu)
    check cpu.state == oldS
    check mem == oldM
  
  test "rF == flags":
    var
      mem = newSeq[uint8](8)
      mcu = newMcu(addr mem)
      cpu = newCpu(mcu)
    cpu.state.flags = { fCarry, fHalfCarry, fAddSub, fZero }
    check cpu.state[rF] == 0b11110000
