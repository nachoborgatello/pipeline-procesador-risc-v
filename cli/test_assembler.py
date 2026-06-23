#!/usr/bin/env python3
"""Tests unitarios del ensamblador RISC-V."""

from riscv_cli import RISCVAssembler

def test_assembler():
    asm = RISCVAssembler()
    errors = 0
    total = 0

    def check(description, source, expected):
        nonlocal errors, total
        total += 1
        try:
            result = asm.assemble(source)
            if expected is None:
                # Solo verificar que no lanza excepcion
                print(f"  OK:   {description} ({len(result)} instrucciones)")
                return
            if len(result) != len(expected):
                print(f"  FAIL: {description}")
                print(f"    Cantidad: esperado {len(expected)}, obtenido {len(result)}")
                errors += 1
                return
            for i, (r, e) in enumerate(zip(result, expected)):
                if r != e:
                    print(f"  FAIL: {description} [instr {i}]")
                    print(f"    Esperado: 0x{e:08X}")
                    print(f"    Obtenido: 0x{r:08X}")
                    errors += 1
                    return
            print(f"  OK:   {description}")
        except Exception as ex:
            print(f"  FAIL: {description}")
            print(f"    Excepcion: {ex}")
            errors += 1

    print("=" * 50)
    print("Tests del ensamblador RISC-V")
    print("=" * 50)

    # R-type
    check("add x3, x1, x2",  "add x3, x1, x2",  [0x002081B3])
    check("sub x3, x1, x2",  "sub x3, x1, x2",  [0x402081B3])
    check("and x5, x6, x7",  "and x5, x6, x7",  [0x007372B3])
    check("or x5, x6, x7",   "or x5, x6, x7",   [0x007362B3])
    check("xor x5, x6, x7",  "xor x5, x6, x7",  [0x007342B3])
    check("sll x5, x6, x7",  "sll x5, x6, x7",  [0x007312B3])
    check("srl x5, x6, x7",  "srl x5, x6, x7",  [0x007352B3])
    check("sra x5, x6, x7",  "sra x5, x6, x7",  [0x407352B3])
    check("slt x5, x6, x7",  "slt x5, x6, x7",  [0x007322B3])
    check("sltu x5, x6, x7", "sltu x5, x6, x7", [0x007332B3])

    # I-type ALU
    check("addi x1, x0, 5",    "addi x1, x0, 5",    [0x00500093])
    check("addi x2, x0, 10",   "addi x2, x0, 10",   [0x00A00113])
    check("andi x3, x1, 0xFF", "andi x3, x1, 0xFF", [0x0FF0F193])
    check("ori x3, x1, 0x10",  "ori x3, x1, 0x10",  [0x0100E193])
    check("xori x3, x1, 7",    "xori x3, x1, 7",    [0x0070C193])
    check("slti x3, x1, 10",   "slti x3, x1, 10",   [0x00A0A193])
    check("sltiu x3, x1, 10",  "sltiu x3, x1, 10",  [0x00A0B193])

    # I-type shifts
    check("slli x3, x1, 4",  "slli x3, x1, 4",  [0x00409193])
    check("srli x3, x1, 4",  "srli x3, x1, 4",  [0x0040D193])
    check("srai x3, x1, 4",  "srai x3, x1, 4",  [0x4040D193])

    # Loads
    check("lw x5, 0(x0)",   "lw x5, 0(x0)",   [0x00002283])
    check("lw x5, 4(x1)",   "lw x5, 4(x1)",   [0x0040A283])
    check("lb x6, 0(x1)",   "lb x6, 0(x1)",   [0x00008303])
    check("lh x6, 2(x1)",   "lh x6, 2(x1)",   [0x00209303])
    check("lbu x6, 0(x1)",  "lbu x6, 0(x1)",  [0x0000C303])
    check("lhu x6, 2(x1)",  "lhu x6, 2(x1)",  [0x0020D303])

    # Stores
    check("sw x4, 0(x0)",   "sw x4, 0(x0)",   [0x00402023])
    check("sw x4, 4(x0)",   "sw x4, 4(x0)",   [0x00402223])
    check("sb x4, 0(x0)",   "sb x4, 0(x0)",   [0x00400023])
    check("sh x5, 4(x0)",   "sh x5, 4(x0)",   [0x00501223])

    # LUI
    check("lui x1, 0xDEADB", "lui x1, 0xDEADB", [0xDEADB0B7])
    check("lui x2, 0x00001", "lui x2, 0x00001", [0x00001137])

    # JAL
    check("jal x1, 12",  "jal x1, 12",  [0x00C000EF])

    # JALR
    check("jalr x4, x3, 0", "jalr x4, x3, 0", [0x00018267])

    # BEQ / BNE
    check("beq x6, x12, 16", "beq x6, x12, 16", [0x00C30863])
    check("bne x1, x2, 8",   "bne x1, x2, 8",   [0x00209463])

    # Pseudo-instrucciones
    check("nop",  "nop",  [0x00000013])
    check("halt", "halt", [0xFFFFFFFF])

    # Programa completo (mismo que tb_debug_unit)
    check("programa tb_debug_unit",
        "addi x1, x0, 5\naddi x2, x0, 10\nadd x3, x1, x2\nhalt",
        [0x00500093, 0x00A00113, 0x002081B3, 0xFFFFFFFF])

    # Labels
    check("programa con labels",
        "addi x1, x0, 1\nbeq x1, x0, skip\naddi x2, x0, 99\nskip: addi x3, x0, 42",
        None)  # Solo verificar que no falla

    # Nombres ABI
    check("nombres ABI", "addi t0, zero, 5", [0x00500293])

    print("=" * 50)
    print(f"Resultados: {total - errors}/{total} pasaron")
    if errors:
        print(f"  {errors} FALLARON")
    else:
        print("  TODOS LOS TESTS PASARON")
    print("=" * 50)
    return errors == 0


if __name__ == "__main__":
    ok = test_assembler()
    exit(0 if ok else 1)
