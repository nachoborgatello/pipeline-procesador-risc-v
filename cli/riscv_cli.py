#!/usr/bin/env python3
"""
RISC-V Pipeline Debugger — CLI/TUI
Comunicacion con la FPGA via UART serial.

Uso:
    python riscv_cli.py                     (auto-detecta puerto)
    python riscv_cli.py --port COM3         (puerto especifico)
    python riscv_cli.py --port COM3 --baud 115200
"""

import argparse
import sys
import struct
import time
import re
import os

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("ERROR: pyserial no instalado. Ejecutar: pip install pyserial")
    sys.exit(1)

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.text import Text
    from rich import box
except ImportError:
    print("ERROR: rich no instalado. Ejecutar: pip install rich")
    sys.exit(1)


# ============================================================
# Constantes del protocolo (deben coincidir con debug_unit.v)
# ============================================================
CMD_LOAD    = 0x01
CMD_RUN     = 0x02
CMD_STEP    = 0x03
CMD_REGS    = 0x04
CMD_LATCHES = 0x05
CMD_MEM     = 0x06
CMD_PC      = 0x07
CMD_RESET   = 0x08

# Nombres ABI de los registros RISC-V
REG_ABI = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0",   "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6",   "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8",   "s9", "s10","s11","t3", "t4", "t5", "t6",
]

console = Console()


# ============================================================
# Ensamblador RISC-V minimo
# ============================================================
class RISCVAssembler:
    """Traduce assembly RISC-V a codigo maquina de 32 bits."""

    # Mapeo registro -> numero
    REG_MAP = {f"x{i}": i for i in range(32)}
    REG_MAP.update({name: i for i, name in enumerate(REG_ABI)})
    # Aliases
    REG_MAP["fp"] = 8  # frame pointer = s0

    # Opcodes R-type
    R_TYPE = {
        "add":  (0x33, 0x0, 0x00),
        "sub":  (0x33, 0x0, 0x20),
        "sll":  (0x33, 0x1, 0x00),
        "srl":  (0x33, 0x5, 0x00),
        "sra":  (0x33, 0x5, 0x20),
        "and":  (0x33, 0x7, 0x00),
        "or":   (0x33, 0x6, 0x00),
        "xor":  (0x33, 0x4, 0x00),
        "slt":  (0x33, 0x2, 0x00),
        "sltu": (0x33, 0x3, 0x00),
    }

    # I-type ALU
    I_TYPE_ALU = {
        "addi":  (0x13, 0x0),
        "andi":  (0x13, 0x7),
        "ori":   (0x13, 0x6),
        "xori":  (0x13, 0x4),
        "slti":  (0x13, 0x2),
        "sltiu": (0x13, 0x3),
    }

    # I-type shifts
    I_TYPE_SHIFT = {
        "slli": (0x13, 0x1, 0x00),
        "srli": (0x13, 0x5, 0x00),
        "srai": (0x13, 0x5, 0x20),
    }

    # I-type loads
    I_TYPE_LOAD = {
        "lb":  (0x03, 0x0),
        "lh":  (0x03, 0x1),
        "lw":  (0x03, 0x2),
        "lbu": (0x03, 0x4),
        "lhu": (0x03, 0x5),
    }

    # S-type stores
    S_TYPE = {
        "sb": (0x23, 0x0),
        "sh": (0x23, 0x1),
        "sw": (0x23, 0x2),
    }

    # B-type branches
    B_TYPE = {
        "beq": (0x63, 0x0),
        "bne": (0x63, 0x1),
    }

    def __init__(self):
        self.labels = {}
        self.instructions = []

    def _parse_reg(self, s):
        s = s.strip().lower()
        if s in self.REG_MAP:
            return self.REG_MAP[s]
        raise ValueError(f"Registro desconocido: '{s}'")

    def _parse_imm(self, s, bits=12):
        s = s.strip()
        # Podria ser un label
        if s in self.labels:
            return self.labels[s]
        # Valor numerico
        val = int(s, 0)
        return val & ((1 << bits) - 1)

    def _parse_imm_signed(self, s, bits=12):
        s = s.strip()
        if s in self.labels:
            val = self.labels[s]
        else:
            val = int(s, 0)
        # Truncar a bits
        mask = (1 << bits) - 1
        return val & mask

    def _parse_mem_operand(self, s):
        """Parsea 'imm(rs1)' -> (imm, rs1_num)."""
        m = re.match(r'(-?\w+)\((\w+)\)', s.strip())
        if not m:
            raise ValueError(f"Formato de memoria invalido: '{s}' (esperado: imm(reg))")
        imm = int(m.group(1), 0)
        rs1 = self._parse_reg(m.group(2))
        return imm, rs1

    def _encode_r(self, mnemonic, args):
        opcode, funct3, funct7 = self.R_TYPE[mnemonic]
        rd  = self._parse_reg(args[0])
        rs1 = self._parse_reg(args[1])
        rs2 = self._parse_reg(args[2])
        return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    def _encode_i_alu(self, mnemonic, args):
        opcode, funct3 = self.I_TYPE_ALU[mnemonic]
        rd  = self._parse_reg(args[0])
        rs1 = self._parse_reg(args[1])
        imm = self._parse_imm_signed(args[2], 12)
        return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    def _encode_i_shift(self, mnemonic, args):
        opcode, funct3, funct7 = self.I_TYPE_SHIFT[mnemonic]
        rd    = self._parse_reg(args[0])
        rs1   = self._parse_reg(args[1])
        shamt = int(args[2].strip(), 0) & 0x1F
        return (funct7 << 25) | (shamt << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    def _encode_load(self, mnemonic, args):
        opcode, funct3 = self.I_TYPE_LOAD[mnemonic]
        rd = self._parse_reg(args[0])
        imm, rs1 = self._parse_mem_operand(args[1])
        imm12 = imm & 0xFFF
        return (imm12 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    def _encode_store(self, mnemonic, args):
        opcode, funct3 = self.S_TYPE[mnemonic]
        rs2 = self._parse_reg(args[0])
        imm, rs1 = self._parse_mem_operand(args[1])
        imm12 = imm & 0xFFF
        imm_hi = (imm12 >> 5) & 0x7F
        imm_lo = imm12 & 0x1F
        return (imm_hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_lo << 7) | opcode

    def _encode_branch(self, mnemonic, args, current_addr):
        opcode, funct3 = self.B_TYPE[mnemonic]
        rs1 = self._parse_reg(args[0])
        rs2 = self._parse_reg(args[1])
        target_str = args[2].strip()
        if target_str in self.labels:
            offset = self.labels[target_str] - current_addr
        else:
            offset = int(target_str, 0)
        # Codificar offset B-type
        imm = offset & 0x1FFF  # 13 bits
        b12   = (imm >> 12) & 0x1
        b10_5 = (imm >> 5)  & 0x3F
        b4_1  = (imm >> 1)  & 0xF
        b11   = (imm >> 11) & 0x1
        return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
               (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode

    def _encode_jal(self, args, current_addr):
        rd = self._parse_reg(args[0])
        target_str = args[1].strip()
        if target_str in self.labels:
            offset = self.labels[target_str] - current_addr
        else:
            offset = int(target_str, 0)
        imm = offset & 0x1FFFFF  # 21 bits
        b20    = (imm >> 20) & 0x1
        b10_1  = (imm >> 1)  & 0x3FF
        b11    = (imm >> 11) & 0x1
        b19_12 = (imm >> 12) & 0xFF
        return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | 0x6F

    def _encode_jalr(self, args):
        rd  = self._parse_reg(args[0])
        rs1 = self._parse_reg(args[1])
        imm = self._parse_imm_signed(args[2], 12)
        return (imm << 20) | (rs1 << 15) | (0x0 << 12) | (rd << 7) | 0x67

    def _encode_lui(self, args):
        rd = self._parse_reg(args[0])
        imm_str = args[1].strip()
        imm = int(imm_str, 0) & 0xFFFFF
        return (imm << 12) | (rd << 7) | 0x37

    def assemble(self, source):
        """Ensambla codigo fuente. Retorna lista de enteros de 32 bits."""
        lines = source.strip().split('\n')

        # --- Pase 1: recolectar labels ---
        self.labels = {}
        self.instructions = []
        addr = 0
        for line in lines:
            line = line.split('#')[0].split('//')[0].strip()
            if not line:
                continue
            # Detectar label
            if ':' in line:
                label_part, rest = line.split(':', 1)
                self.labels[label_part.strip()] = addr
                line = rest.strip()
                if not line:
                    continue
            self.instructions.append((addr, line))
            addr += 4

        # --- Pase 2: codificar ---
        machine_code = []
        for addr, line in self.instructions:
            # Separar mnemonic y operandos
            parts = line.split(None, 1)
            mnemonic = parts[0].lower()
            args = []
            if len(parts) > 1:
                args = [a.strip() for a in parts[1].split(',')]

            try:
                if mnemonic == "halt":
                    code = 0xFFFFFFFF
                elif mnemonic == "nop":
                    code = 0x00000013  # addi x0, x0, 0
                elif mnemonic in self.R_TYPE:
                    code = self._encode_r(mnemonic, args)
                elif mnemonic in self.I_TYPE_ALU:
                    code = self._encode_i_alu(mnemonic, args)
                elif mnemonic in self.I_TYPE_SHIFT:
                    code = self._encode_i_shift(mnemonic, args)
                elif mnemonic in self.I_TYPE_LOAD:
                    code = self._encode_load(mnemonic, args)
                elif mnemonic in self.S_TYPE:
                    code = self._encode_store(mnemonic, args)
                elif mnemonic in self.B_TYPE:
                    code = self._encode_branch(mnemonic, args, addr)
                elif mnemonic == "jal":
                    code = self._encode_jal(args, addr)
                elif mnemonic == "jalr":
                    code = self._encode_jalr(args)
                elif mnemonic == "lui":
                    code = self._encode_lui(args)
                else:
                    raise ValueError(f"Instruccion desconocida: '{mnemonic}'")

                machine_code.append(code & 0xFFFFFFFF)
            except Exception as e:
                raise ValueError(f"Error en linea (addr 0x{addr:04X}): '{line}'\n  {e}")

        return machine_code

    def assemble_file(self, filepath):
        """Lee un archivo .asm y lo ensambla."""
        with open(filepath, 'r', encoding='utf-8') as f:
            source = f.read()
        return self.assemble(source)


# ============================================================
# Comunicacion con la FPGA
# ============================================================
class FPGADebugger:
    """Maneja la comunicacion serial con la Debug Unit."""

    def __init__(self, port, baud=115200, timeout=5):
        self.ser = serial.Serial(port, baud, timeout=timeout)
        time.sleep(0.1)  # Esperar a que el puerto se estabilice
        self.ser.reset_input_buffer()

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()

    def _send_byte(self, val):
        self.ser.write(bytes([val & 0xFF]))

    def _send_word(self, val):
        """Envia un word de 32 bits, big-endian (4 bytes)."""
        self.ser.write(struct.pack('>I', val & 0xFFFFFFFF))

    def _recv_byte(self):
        data = self.ser.read(1)
        if len(data) != 1:
            raise TimeoutError("Timeout esperando byte de la FPGA")
        return data[0]

    def _recv_word(self):
        """Recibe un word de 32 bits, big-endian."""
        data = self.ser.read(4)
        if len(data) != 4:
            raise TimeoutError(f"Timeout esperando word (recibidos {len(data)} bytes)")
        return struct.unpack('>I', data)[0]

    # --- Comandos ---

    def load_program(self, words):
        """CMD_LOAD: carga lista de words en la memoria de instrucciones."""
        n = len(words)
        if n == 0:
            raise ValueError("Programa vacio")
        if n > 256:
            raise ValueError(f"Programa demasiado largo ({n} instrucciones, max 256)")

        self._send_byte(CMD_LOAD)
        self._send_byte((n >> 8) & 0xFF)  # len_hi
        self._send_byte(n & 0xFF)          # len_lo

        for w in words:
            self._send_word(w)

        time.sleep(0.05)

    def run(self):
        """CMD_RUN: ejecuta en modo continuo hasta HALT."""
        self._send_byte(CMD_RUN)
        time.sleep(0.05)

    def step(self):
        """CMD_STEP: ejecuta un ciclo de reloj."""
        self._send_byte(CMD_STEP)
        time.sleep(0.01)

    def get_regs(self):
        """CMD_REGS: lee los 32 registros. Retorna lista de 32 ints."""
        self._send_byte(CMD_REGS)
        regs = []
        for _ in range(32):
            regs.append(self._recv_word())
        return regs

    def get_latches(self):
        """CMD_LATCHES: lee words de latch de la FPGA (LATCH_WORDS=18 en bitstream)."""
        self._send_byte(CMD_LATCHES)
        # Leer TODOS los bytes que la FPGA envia (18 words = 72 bytes) de golpe
        raw = self.ser.read(18 * 4)
        if len(raw) < 17 * 4:
            raise TimeoutError(f"Timeout leyendo latches (recibidos {len(raw)} bytes, esperados {18*4})")
        # Decodificar solo los primeros 17 words utiles
        words = []
        for i in range(17):
            w = struct.unpack('>I', raw[i*4:(i+1)*4])[0]
            words.append(w)

        return {
            "IF/ID": {
                "PC":    words[0],
                "Instr": words[1],
            },
            "ID/EX": {
                "PC":        words[2],
                "rs1_data":  words[3],
                "rs2_data":  words[4],
                "imm":       words[5],
                "rd|opcode": words[6],
                "ctrl":      words[7],
            },
            "EX/MEM": {
                "ALU result":    words[8],
                "rs2_data":      words[9],
                "rd":            words[10],
                "PC+4":          words[11],
                "branch_target": words[12],
            },
            "MEM/WB": {
                "read_data":  words[13],
                "ALU result": words[14],
                "rd":         words[15],
                "PC+4":       words[16],
            },
        }

    def get_mem(self, addr, length):
        """CMD_MEM: lee 'length' words de data memory desde 'addr'."""
        self._send_byte(CMD_MEM)
        self._send_byte((addr >> 8) & 0xFF)
        self._send_byte(addr & 0xFF)
        self._send_byte((length >> 8) & 0xFF)
        self._send_byte(length & 0xFF)
        words = []
        for _ in range(length):
            words.append(self._recv_word())
        return words

    def get_pc(self):
        """CMD_PC: lee el PC actual."""
        self._send_byte(CMD_PC)
        return self._recv_word()

    def reset(self):
        """CMD_RESET: resetea el pipeline."""
        self._send_byte(CMD_RESET)
        time.sleep(0.05)


# ============================================================
# Utilidades de display
# ============================================================

def display_regs(regs):
    """Muestra los 32 registros en una tabla."""
    table = Table(
        title="Registros RISC-V",
        box=box.ROUNDED,
        show_lines=True,
    )
    table.add_column("Reg", style="cyan", width=6)
    table.add_column("ABI", style="green", width=6)
    table.add_column("Hex", style="yellow", width=12)
    table.add_column("Dec", style="white", width=12)
    table.add_column("", width=2)
    table.add_column("Reg", style="cyan", width=6)
    table.add_column("ABI", style="green", width=6)
    table.add_column("Hex", style="yellow", width=12)
    table.add_column("Dec", style="white", width=12)

    for i in range(16):
        j = i + 16
        vi = regs[i]
        vj = regs[j]
        # Interpretar como signed
        si = vi if vi < 0x80000000 else vi - 0x100000000
        sj = vj if vj < 0x80000000 else vj - 0x100000000
        table.add_row(
            f"x{i}", REG_ABI[i], f"0x{vi:08X}", str(si),
            "",
            f"x{j}", REG_ABI[j], f"0x{vj:08X}", str(sj),
        )

    console.print(table)


def display_latches(latches):
    """Muestra el contenido de los latches inter-etapa."""
    for stage_name, fields in latches.items():
        table = Table(title=f"Latch {stage_name}", box=box.SIMPLE_HEAVY)
        table.add_column("Campo", style="cyan")
        table.add_column("Valor", style="yellow")
        for fname, fval in fields.items():
            table.add_row(fname, f"0x{fval:08X}")
        console.print(table)


def display_mem(words, base_addr):
    """Muestra memoria de datos."""
    table = Table(title="Data Memory", box=box.ROUNDED)
    table.add_column("Addr", style="cyan", width=10)
    table.add_column("Hex", style="yellow", width=12)
    table.add_column("Dec", style="white", width=12)
    for i, w in enumerate(words):
        addr = base_addr + i * 4
        s = w if w < 0x80000000 else w - 0x100000000
        table.add_row(f"0x{addr:04X}", f"0x{w:08X}", str(s))
    console.print(table)


def display_program(words):
    """Muestra programa ensamblado."""
    table = Table(title="Programa ensamblado", box=box.ROUNDED)
    table.add_column("Addr", style="cyan", width=8)
    table.add_column("Machine Code", style="yellow", width=12)
    for i, w in enumerate(words):
        table.add_row(f"0x{i*4:04X}", f"0x{w:08X}")
    console.print(table)


# ============================================================
# CLI principal
# ============================================================

HELP_TEXT = """
[bold cyan]Comandos disponibles:[/bold cyan]

  [green]load[/green] <archivo.asm>     Ensambla y carga programa en la FPGA
  [green]run[/green]                    Ejecuta programa hasta HALT (modo continuo)
  [green]step[/green]                   Ejecuta un ciclo de reloj (modo paso a paso)
  [green]regs[/green]                   Muestra los 32 registros
  [green]latches[/green]                Muestra contenido de latches inter-etapa
  [green]mem[/green] <addr> <len>       Lee 'len' words de memoria desde 'addr'
  [green]pc[/green]                     Muestra el Program Counter actual
  [green]reset[/green]                  Resetea el pipeline
  [green]asm[/green] <archivo.asm>      Solo ensambla y muestra (no carga)
  [green]help[/green]                   Muestra esta ayuda
  [green]exit[/green]                   Salir
"""


def find_serial_port():
    """Intenta detectar automaticamente el puerto serial de la FPGA."""
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        return None
    # Buscar puertos tipicos de FPGA (FTDI, Digilent, etc.)
    for p in ports:
        desc = (p.description or "").lower()
        manuf = (p.manufacturer or "").lower()
        if any(kw in desc for kw in ["ftdi", "digilent", "uart", "usb serial"]):
            return p.device
        if any(kw in manuf for kw in ["ftdi", "digilent"]):
            return p.device
    # Si no encontramos nada especifico, retornar el primero
    return ports[0].device


def main():
    parser = argparse.ArgumentParser(description="RISC-V Pipeline Debugger CLI")
    parser.add_argument("--port", "-p", help="Puerto serial (ej: COM3, /dev/ttyUSB0)")
    parser.add_argument("--baud", "-b", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--timeout", "-t", type=float, default=5.0, help="Timeout serial en segundos")
    args = parser.parse_args()

    # Banner
    console.print(Panel(
        "[bold cyan]RISC-V Pipeline Debugger[/bold cyan]\n"
        "[dim]Arquitectura de Computadoras — TP Final 2025[/dim]",
        border_style="cyan",
    ))

    # Conectar
    port = args.port or find_serial_port()
    if port is None:
        console.print("[bold red]No se encontro puerto serial.[/bold red]")
        console.print("Usar: python riscv_cli.py --port COM3")
        sys.exit(1)

    try:
        dbg = FPGADebugger(port, args.baud, args.timeout)
        console.print(f"[green]Conectado a {port} @ {args.baud} baud[/green]")
    except serial.SerialException as e:
        console.print(f"[bold red]Error al abrir {port}:[/bold red] {e}")
        sys.exit(1)

    asm = RISCVAssembler()

    # Loop principal
    console.print("Escribir [green]help[/green] para ver comandos.\n")
    while True:
        try:
            raw = console.input("[bold cyan]riscv>[/bold cyan] ").strip()
        except (EOFError, KeyboardInterrupt):
            console.print("\nSaliendo...")
            break

        if not raw:
            continue

        parts = raw.split()
        cmd = parts[0].lower()
        cmd_args = parts[1:]

        try:
            if cmd in ("exit", "quit", "q"):
                break

            elif cmd == "help":
                console.print(HELP_TEXT)

            elif cmd == "load":
                if not cmd_args:
                    console.print("[red]Uso: load <archivo.asm>[/red]")
                    continue
                filepath = cmd_args[0]
                if not os.path.isfile(filepath):
                    console.print(f"[red]Archivo no encontrado: {filepath}[/red]")
                    continue
                words = asm.assemble_file(filepath)
                display_program(words)
                console.print(f"Cargando {len(words)} instrucciones...")
                dbg.load_program(words)
                dbg.reset()
                console.print(f"[green]Programa cargado y pipeline reseteado.[/green]")

            elif cmd == "run":
                console.print("Ejecutando programa (modo continuo)...")
                dbg.run()
                time.sleep(0.2)
                pc = dbg.get_pc()
                console.print(f"[green]Ejecucion finalizada.[/green] PC = 0x{pc:08X}")

            elif cmd == "step":
                dbg.step()
                pc = dbg.get_pc()
                console.print(f"[yellow]Step[/yellow] — PC = 0x{pc:08X}")

            elif cmd == "regs":
                regs = dbg.get_regs()
                display_regs(regs)

            elif cmd == "latches":
                latches = dbg.get_latches()
                display_latches(latches)

            elif cmd == "mem":
                if len(cmd_args) < 2:
                    console.print("[red]Uso: mem <addr> <len>[/red]")
                    console.print("  addr: direccion base (hex o dec)")
                    console.print("  len:  cantidad de words a leer")
                    continue
                addr = int(cmd_args[0], 0)
                length = int(cmd_args[1], 0)
                words = dbg.get_mem(addr, length)
                display_mem(words, addr)

            elif cmd == "pc":
                pc = dbg.get_pc()
                console.print(f"PC = [yellow]0x{pc:08X}[/yellow] ({pc})")

            elif cmd == "reset":
                dbg.reset()
                console.print("[green]Pipeline reseteado.[/green]")

            elif cmd == "asm":
                if not cmd_args:
                    console.print("[red]Uso: asm <archivo.asm>[/red]")
                    continue
                filepath = cmd_args[0]
                if not os.path.isfile(filepath):
                    console.print(f"[red]Archivo no encontrado: {filepath}[/red]")
                    continue
                words = asm.assemble_file(filepath)
                display_program(words)
                console.print(f"[dim]{len(words)} instrucciones ensambladas (no cargadas).[/dim]")

            else:
                console.print(f"[red]Comando desconocido: '{cmd}'[/red]. Escribir [green]help[/green] para ayuda.")

        except TimeoutError as e:
            console.print(f"[bold red]Timeout:[/bold red] {e}")
        except ValueError as e:
            console.print(f"[bold red]Error:[/bold red] {e}")
        except serial.SerialException as e:
            console.print(f"[bold red]Error serial:[/bold red] {e}")
        except Exception as e:
            console.print(f"[bold red]Error inesperado:[/bold red] {e}")

    dbg.close()
    console.print("[dim]Conexion cerrada.[/dim]")


if __name__ == "__main__":
    main()
