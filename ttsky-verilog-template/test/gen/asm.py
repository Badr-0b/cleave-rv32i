#!/usr/bin/env python3
# Minimal RV32I assembler + ISS — generator for the Cleave proof program.
#
# LOAD-BEARING: this is the source of truth for two committed files. Editing the
# program below and re-running regenerates:
#   (a) the ROM lines pasted into  src/cleave_imem.v      (the synthesized program)
#   (b) the golden regfile/memory in test/unit/tb_cleave_proof.v (the bench oracle)
# The ISS here and the Verilog RTL are independent models that cross-check each other.
#
# Regenerate:  python test/gen/asm.py     (run from ttsky-verilog-template/)
# then copy the emitted ROM/golden blocks into the two files above and re-run
# test/unit/run_unit_tests.ps1 (expect 10/10). Encoders + ISS verified against the
# RV32I spec and by independent hand-decode of the committed hex.

import sys

MASK = 0xFFFFFFFF

def u32(x): return x & MASK
def sx(v, bits):
    s = 1 << (bits - 1)
    return (v ^ s) - s

# ---- encoders ----------------------------------------------------------------
def R(f7, rs2, rs1, f3, rd, op): return u32((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def I(imm, rs1, f3, rd, op):
    imm &= 0xFFF
    return u32((imm<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def Ish(f7, sh, rs1, f3, rd, op): return u32((f7<<25)|((sh&0x1F)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def S(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return u32(((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|op)
def B(imm, rs2, rs1, f3, op):
    imm &= 0x1FFF
    b12=(imm>>12)&1; b11=(imm>>11)&1; b10_5=(imm>>5)&0x3F; b4_1=(imm>>1)&0xF
    return u32((b12<<31)|(b10_5<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(b4_1<<8)|(b11<<7)|op)
def U(imm, rd, op): return u32(((imm&0xFFFFF)<<12)|(rd<<7)|op)
def J(imm, rd, op):
    imm &= 0x1FFFFF
    b20=(imm>>20)&1; b10_1=(imm>>1)&0x3FF; b11=(imm>>11)&1; b19_12=(imm>>12)&0xFF
    return u32((b20<<31)|(b10_1<<21)|(b11<<20)|(b19_12<<12)|(rd<<7)|op)

OP_LUI,OP_AUIPC,OP_JAL,OP_JALR = 0x37,0x17,0x6F,0x67
OP_BR,OP_LD,OP_ST,OP_IMM,OP_REG = 0x63,0x03,0x23,0x13,0x33
OP_FENCE,OP_SYS = 0x0F,0x73

# ---- program: list of (label_or_None, mnemonic, args) ------------------------
# args are ints (regs as 'xN') resolved below. Branches/jumps use labels.
P = [
 # ---- ALU immediate ----
 (None,"addi",("x3","x0",100)),
 (None,"addi",("x4","x0",-50)),        # 0xFFFFFFCE
 (None,"xori",("x7","x3",0xF0)),
 (None,"ori", ("x8","x3",1)),
 (None,"andi",("x9","x3",0x0F)),       # x9 = 4  (also used as shift amount)
 (None,"slti",("x10","x4",0)),
 (None,"sltiu",("x11","x4",0)),
 (None,"slli",("x12","x3",4)),
 (None,"srli",("x13","x3",2)),
 (None,"srai",("x14","x4",1)),
 # ---- ALU register (shift amount = x9 = 4) ----
 (None,"add", ("x5","x3","x4")),
 (None,"sub", ("x6","x3","x4")),
 (None,"sll", ("x15","x3","x9")),
 (None,"srl", ("x17","x3","x9")),
 (None,"sra", ("x18","x4","x9")),
 (None,"slt", ("x19","x4","x3")),
 (None,"sltu",("x20","x3","x4")),
 (None,"xor", ("x21","x3","x4")),
 (None,"or",  ("x22","x3","x9")),
 (None,"and", ("x23","x3","x9")),
 # ---- U-type ----
 (None,"lui",  ("x1",0x12345)),
 (None,"auipc",("x2",0)),
 # ---- memory: word/half/byte loads + SB/SH stores ----
 (None,"addi",("x24","x0",16)),        # data base byte 16 (word 4)
 (None,"lui", ("x25",0xDEADC)),
 (None,"ori", ("x25","x25",0xDE)),     # x25 = 0xDEADC0DE
 (None,"sw",  ("x25",0,"x24")),        # mem[16] = 0xDEADC0DE
 (None,"lw",  ("x26",0,"x24")),
 (None,"lh",  ("x27",0,"x24")),        # 0xFFFFC0DE
 (None,"lhu", ("x28",0,"x24")),        # 0x0000C0DE
 (None,"lb",  ("x29",0,"x24")),        # 0xFFFFFFDE
 (None,"lbu", ("x30",1,"x24")),        # 0x000000C0
 (None,"sb",  ("x25",8,"x24")),        # mem byte 24 (word6) low byte = 0xDE
 (None,"sh",  ("x25",12,"x24")),       # mem byte 28 (word7) low half = 0xC0DE
 # ---- control flow: witness accumulator in x31 ----
 (None,"addi",("x31","x0",0)),
 (None,"beq", ("x0","x0","L1")),
 (None,"addi",("x31","x31",0x100)),    # POISON
 ("L1","addi",("x31","x31",1)),
 (None,"bne", ("x3","x4","L2")),
 (None,"addi",("x31","x31",0x200)),    # POISON
 ("L2","addi",("x31","x31",2)),
 (None,"blt", ("x4","x3","L3")),
 (None,"addi",("x31","x31",0x400)),    # POISON
 ("L3","addi",("x31","x31",4)),
 (None,"bge", ("x3","x4","L4")),
 (None,"addi",("x31","x31",0x400)),    # POISON
 ("L4","addi",("x31","x31",8)),
 (None,"bltu",("x3","x4","L5")),
 (None,"addi",("x31","x31",0x400)),    # POISON
 ("L5","addi",("x31","x31",16)),
 (None,"bgeu",("x4","x3","L6")),
 (None,"addi",("x31","x31",0x400)),    # POISON
 ("L6","addi",("x31","x31",32)),
 # not-taken branches must fall through
 (None,"beq", ("x3","x4","L7")),       # not taken
 (None,"addi",("x31","x31",64)),       # MUST execute
 ("L7","bne", ("x3","x3","L8")),       # not taken (equal)
 (None,"addi",("x31","x31",128)),      # MUST execute  -> witness = 0xFF
 # ---- JAL / JALR subroutine ----
 ("L8","jal", ("x16","SUB")),          # link in x16 (leaves x5 = ADD result to check)
 (None,"addi",("x31","x31",256)),      # after return -> witness = 0x1FF
 (None,"jal", ("x0","DONE")),          # J DONE (skip subroutine body)
 ("SUB","sub", ("x6","x3","x4")),      # x6 = 100-(-50) = 150 (tests SUB + proves call ran)
 (None,"jalr",("x0","x16",0)),         # return via x16
 # ---- SYSTEM/FENCE decode-as-NOP coverage ----
 ("DONE","fence",()),
 (None,"ecall",()),
 # ---- park ----
 (None,"beq", ("x0","x0","PARK")),     # self-loop
]

def reg(a): return int(a[1:]) if isinstance(a,str) and a[0]=='x' else a

# pass 1: assign addresses + labels
labels={}
addr=0
for (lab,mn,args) in P:
    if lab: labels[lab]=addr
    addr+=4
if len(P)>64:
    print("ERROR: program has %d instructions (>64)"%len(P)); sys.exit(1)

# pass 2: encode
rom=[]
pc=0
for (lab,mn,args) in P:
    a=args
    if mn=="addi": w=I(a[2],reg(a[1]),0,reg(a[0]),OP_IMM)
    elif mn=="xori":w=I(a[2],reg(a[1]),4,reg(a[0]),OP_IMM)
    elif mn=="ori": w=I(a[2],reg(a[1]),6,reg(a[0]),OP_IMM)
    elif mn=="andi":w=I(a[2],reg(a[1]),7,reg(a[0]),OP_IMM)
    elif mn=="slti":w=I(a[2],reg(a[1]),2,reg(a[0]),OP_IMM)
    elif mn=="sltiu":w=I(a[2],reg(a[1]),3,reg(a[0]),OP_IMM)
    elif mn=="slli":w=Ish(0x00,a[2],reg(a[1]),1,reg(a[0]),OP_IMM)
    elif mn=="srli":w=Ish(0x00,a[2],reg(a[1]),5,reg(a[0]),OP_IMM)
    elif mn=="srai":w=Ish(0x20,a[2],reg(a[1]),5,reg(a[0]),OP_IMM)
    elif mn=="add": w=R(0x00,reg(a[2]),reg(a[1]),0,reg(a[0]),OP_REG)
    elif mn=="sub": w=R(0x20,reg(a[2]),reg(a[1]),0,reg(a[0]),OP_REG)
    elif mn=="sll": w=R(0x00,reg(a[2]),reg(a[1]),1,reg(a[0]),OP_REG)
    elif mn=="srl": w=R(0x00,reg(a[2]),reg(a[1]),5,reg(a[0]),OP_REG)
    elif mn=="sra": w=R(0x20,reg(a[2]),reg(a[1]),5,reg(a[0]),OP_REG)
    elif mn=="slt": w=R(0x00,reg(a[2]),reg(a[1]),2,reg(a[0]),OP_REG)
    elif mn=="sltu":w=R(0x00,reg(a[2]),reg(a[1]),3,reg(a[0]),OP_REG)
    elif mn=="xor": w=R(0x00,reg(a[2]),reg(a[1]),4,reg(a[0]),OP_REG)
    elif mn=="or":  w=R(0x00,reg(a[2]),reg(a[1]),6,reg(a[0]),OP_REG)
    elif mn=="and": w=R(0x00,reg(a[2]),reg(a[1]),7,reg(a[0]),OP_REG)
    elif mn=="lui": w=U(a[1],reg(a[0]),OP_LUI)
    elif mn=="auipc":w=U(a[1],reg(a[0]),OP_AUIPC)
    elif mn=="lw":  w=I(a[1],reg(a[2]),2,reg(a[0]),OP_LD)
    elif mn=="lh":  w=I(a[1],reg(a[2]),1,reg(a[0]),OP_LD)
    elif mn=="lhu": w=I(a[1],reg(a[2]),5,reg(a[0]),OP_LD)
    elif mn=="lb":  w=I(a[1],reg(a[2]),0,reg(a[0]),OP_LD)
    elif mn=="lbu": w=I(a[1],reg(a[2]),4,reg(a[0]),OP_LD)
    elif mn=="sw":  w=S(a[1],reg(a[0]),reg(a[2]),2,OP_ST)
    elif mn=="sh":  w=S(a[1],reg(a[0]),reg(a[2]),1,OP_ST)
    elif mn=="sb":  w=S(a[1],reg(a[0]),reg(a[2]),0,OP_ST)
    elif mn in ("beq","bne","blt","bge","bltu","bgeu"):
        f3={"beq":0,"bne":1,"blt":4,"bge":5,"bltu":6,"bgeu":7}[mn]
        tgt=labels[a[2]] if a[2]!="PARK" else pc
        w=B(tgt-pc,reg(a[1]),reg(a[0]),f3,OP_BR)
    elif mn=="jal": w=J(labels[a[1]]-pc,reg(a[0]),OP_JAL)
    elif mn=="jalr":w=I(a[2],reg(a[1]),0,reg(a[0]),OP_JALR)
    elif mn=="fence":w=0x0000000F
    elif mn=="ecall":w=0x00000073
    else: raise Exception("unknown "+mn)
    rom.append(w); pc+=4

# ---- ISS: run the encoded program ----
DMEM=[0]*64  # 64 words
R_=[0]*32
pc=0
steps=0
while steps<10000:
    steps+=1
    idx=(pc>>2)&0x3F
    instr=rom[idx]
    op=instr&0x7F
    rd=(instr>>7)&0x1F; f3=(instr>>12)&7; rs1=(instr>>15)&0x1F; rs2=(instr>>20)&0x1F
    f7=(instr>>25)&0x7F
    a=R_[rs1]; b=R_[rs2]
    immI=sx(instr>>20,12)
    immS=sx(((instr>>25)<<5)|((instr>>7)&0x1F),12)
    immB=sx(((instr>>31)<<12)|(((instr>>7)&1)<<11)|(((instr>>25)&0x3F)<<5)|(((instr>>8)&0xF)<<1),13)
    immU=u32(instr&0xFFFFF000)
    immJ=sx(((instr>>31)<<20)|(((instr>>12)&0xFF)<<12)|(((instr>>20)&1)<<11)|(((instr>>21)&0x3FF)<<1),21)
    npc=u32(pc+4)
    def wr(v):
        if rd!=0: R_[rd]=u32(v)
    if op==OP_IMM:
        if f3==0: wr(a+immI)
        elif f3==4: wr(a^ (immI&MASK))
        elif f3==6: wr(a|(immI&MASK))
        elif f3==7: wr(a&(immI&MASK))
        elif f3==2: wr(1 if sx(a,32)<immI else 0)
        elif f3==3: wr(1 if a<(immI&MASK) else 0)
        elif f3==1: wr(a<<(immI&0x1F))
        elif f3==5:
            sh=immI&0x1F
            wr((sx(a,32)>>sh)&MASK if (instr>>30)&1 else a>>sh)
    elif op==OP_REG:
        sh=b&0x1F
        if f3==0: wr(a-b if f7==0x20 else a+b)
        elif f3==1: wr(a<<sh)
        elif f3==5: wr((sx(a,32)>>sh)&MASK if f7==0x20 else a>>sh)
        elif f3==2: wr(1 if sx(a,32)<sx(b,32) else 0)
        elif f3==3: wr(1 if a<b else 0)
        elif f3==4: wr(a^b)
        elif f3==6: wr(a|b)
        elif f3==7: wr(a&b)
    elif op==OP_LUI: wr(immU)
    elif op==OP_AUIPC: wr(pc+immU)
    elif op==OP_LD:
        ea=u32(a+immI); wi=(ea>>2)&0x3F; off=ea&3; word=DMEM[wi]
        if f3==2: wr(word)
        elif f3==0: wr(sx((word>>(8*off))&0xFF,8)&MASK)
        elif f3==4: wr((word>>(8*off))&0xFF)
        elif f3==1: wr(sx((word>>(16*(off>>1)))&0xFFFF,16)&MASK)
        elif f3==5: wr((word>>(16*(off>>1)))&0xFFFF)
    elif op==OP_ST:
        ea=u32(a+immS); wi=(ea>>2)&0x3F; off=ea&3; word=DMEM[wi]; val=b
        if f3==2: DMEM[wi]=u32(val)
        elif f3==0:
            m=0xFF<<(8*off); DMEM[wi]=u32((word&~m)|((val<<(8*off))&m))
        elif f3==1:
            m=0xFFFF<<(8*off); DMEM[wi]=u32((word&~m)|((val<<(8*off))&m))
    elif op==OP_BR:
        take={0:a==b,1:a!=b,4:sx(a,32)<sx(b,32),5:sx(a,32)>=sx(b,32),6:a<b,7:a>=b}[f3]
        if take: npc=u32(pc+immB)
    elif op==OP_JAL: wr(npc); npc=u32(pc+immJ)
    elif op==OP_JALR: t=u32(a+immI)&~1; wr(npc); npc=t
    elif op in (OP_FENCE,OP_SYS): pass
    else: raise Exception("illegal op %02x at pc %x"%(op,pc))
    # park detection: BEQ x0,x0,0 self-loop -> npc==pc
    if npc==pc:
        break
    pc=npc

park_pc=pc
# ---- emit ----
print("// %d instructions, park PC = 0x%X (word %d)"%(len(rom),park_pc,park_pc>>2))
print("\n--- ROM LINES ---")
for i,w in enumerate(rom):
    print("    rom[%2d] = 32'h%08X;"%(i,w))
print("\n--- GOLDEN REGS ---")
for i in range(32):
    print("    golden[%2d] = 32'h%08X;"%(i,R_[i]))
print("\n--- GOLDEN MEM (nonzero words) ---")
for i,wd in enumerate(DMEM):
    if wd: print("    mem word %2d (byte %3d) = 32'h%08X"%(i,i*4,wd))
print("\nwitness x31 = 0x%X (%d)  x6=0x%X  x5(link)=0x%X"%(R_[31],R_[31],R_[6],R_[5]))
