#!/usr/bin/env python3
"""
RISC-V Pipeline Debugger — GUI
Interfaz grafica para comunicacion con la FPGA via UART serial.

Uso:
    python riscv_gui.py
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext
import threading
import re
import time
import os
import sys

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    messagebox.showerror("Dependencia faltante", "pyserial no instalado.\nEjecutar: pip install pyserial")
    sys.exit(1)

# Reutilizar ensamblador y debugger del CLI
from riscv_cli import RISCVAssembler, FPGADebugger, REG_ABI

# ============================================================
# Colores y estilos
# ============================================================
BG_DARK      = "#1e1e2e"
BG_PANEL     = "#282840"
BG_ENTRY     = "#313150"
BG_EDITOR    = "#1a1a2e"
BG_BUTTON    = "#44447a"
BG_BUTTON_OK = "#2d8c4e"
BG_BUTTON_W  = "#b8860b"
BG_BUTTON_R  = "#a83232"
FG_TEXT      = "#cdd6f4"
FG_DIM       = "#6c7086"
FG_CYAN      = "#89dceb"
FG_GREEN     = "#a6e3a1"
FG_YELLOW    = "#f9e2af"
FG_RED       = "#f38ba8"
FG_BLUE      = "#89b4fa"
FG_ACCENT    = "#cba6f7"
FONT_MONO    = ("Consolas", 10)
FONT_MONO_SM = ("Consolas", 9)
FONT_MONO_LG = ("Consolas", 11, "bold")
FONT_TITLE   = ("Segoe UI", 12, "bold")
FONT_LABEL   = ("Segoe UI", 10)
FONT_BTN     = ("Segoe UI", 9, "bold")


class RISCVDebuggerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("RISC-V Pipeline Debugger")
        self.root.configure(bg=BG_DARK)
        self.root.geometry("1200x800")
        self.root.minsize(950, 650)

        self.dbg = None
        self.asm = RISCVAssembler()
        self.loaded_program = None
        self.connected = False
        self._current_file = None
        self._editor_modified = False
        self._highlight_after_id = None
        # Lock serial: evita que multiples threads hablen con la FPGA en simultaneo
        # (causaba bytes mezclados y timeouts al clickear botones en rapida sucesion)
        self._serial_lock = threading.RLock()

        # Pre-calcular keywords y registros para syntax highlighting
        _tmp = RISCVAssembler()
        self._asm_keywords = (
            set(_tmp.R_TYPE) | set(_tmp.I_TYPE_ALU) | set(_tmp.I_TYPE_SHIFT)
            | set(_tmp.I_TYPE_LOAD) | set(_tmp.S_TYPE) | set(_tmp.B_TYPE)
            | {"jal", "jalr", "lui", "halt", "nop"}
        )
        self._asm_registers = {f"x{i}" for i in range(32)} | set(REG_ABI) | {"fp"}

        self._build_styles()
        self._build_ui()
        self._refresh_ports()
        self.log("RISC-V Pipeline Debugger iniciado.")
        self.log("Conectar a la FPGA para comenzar.\n")

    # --------------------------------------------------------
    # Estilos ttk
    # --------------------------------------------------------
    def _build_styles(self):
        style = ttk.Style()
        style.theme_use("clam")

        style.configure("Dark.TFrame", background=BG_DARK)
        style.configure("Panel.TFrame", background=BG_PANEL)
        style.configure("Dark.TLabel", background=BG_DARK, foreground=FG_TEXT, font=FONT_LABEL)
        style.configure("Panel.TLabel", background=BG_PANEL, foreground=FG_TEXT, font=FONT_LABEL)
        style.configure("Title.TLabel", background=BG_DARK, foreground=FG_CYAN, font=FONT_TITLE)
        style.configure("Dim.TLabel", background=BG_DARK, foreground=FG_DIM, font=FONT_LABEL)

        style.configure("Dark.TLabelframe", background=BG_PANEL, foreground=FG_CYAN)
        style.configure("Dark.TLabelframe.Label", background=BG_PANEL, foreground=FG_CYAN, font=FONT_LABEL)

        style.configure("Accent.TButton", background=BG_BUTTON, foreground=FG_TEXT,
                        font=FONT_BTN, padding=(8, 4))
        style.map("Accent.TButton", background=[("active", "#55559a")])

        style.configure("Green.TButton", background=BG_BUTTON_OK, foreground="white",
                        font=FONT_BTN, padding=(8, 4))
        style.map("Green.TButton", background=[("active", "#3aad60")])

        style.configure("Warn.TButton", background=BG_BUTTON_W, foreground="white",
                        font=FONT_BTN, padding=(8, 4))
        style.map("Warn.TButton", background=[("active", "#d4a017")])

        style.configure("Red.TButton", background=BG_BUTTON_R, foreground="white",
                        font=FONT_BTN, padding=(8, 4))
        style.map("Red.TButton", background=[("active", "#c44040")])

        style.configure("Dark.TCombobox", fieldbackground=BG_ENTRY, background=BG_BUTTON,
                        foreground=FG_TEXT, font=FONT_MONO_SM)

        style.configure("Reg.Treeview",
                        background=BG_PANEL, foreground=FG_TEXT, fieldbackground=BG_PANEL,
                        font=FONT_MONO_SM, rowheight=22)
        style.configure("Reg.Treeview.Heading",
                        background=BG_BUTTON, foreground=FG_CYAN, font=FONT_BTN)
        style.map("Reg.Treeview", background=[("selected", "#44447a")])

    # --------------------------------------------------------
    # Construccion de la UI
    # --------------------------------------------------------
    def _build_ui(self):
        # Header
        header = ttk.Frame(self.root, style="Dark.TFrame")
        header.pack(fill=tk.X, padx=10, pady=(10, 5))

        ttk.Label(header, text="RISC-V Pipeline Debugger", style="Title.TLabel").pack(side=tk.LEFT)
        ttk.Label(header, text="Arquitectura de Computadoras — TP Final 2025",
                  style="Dim.TLabel").pack(side=tk.LEFT, padx=(15, 0))

        self.status_label = ttk.Label(header, text="  Desconectado", style="Dark.TLabel",
                                      foreground=FG_RED)
        self.status_label.pack(side=tk.RIGHT)

        # Barra de conexion
        conn_frame = ttk.LabelFrame(self.root, text=" Conexion Serial ", style="Dark.TLabelframe")
        conn_frame.pack(fill=tk.X, padx=10, pady=5)

        inner = ttk.Frame(conn_frame, style="Panel.TFrame")
        inner.pack(fill=tk.X, padx=8, pady=8)

        ttk.Label(inner, text="Puerto:", style="Panel.TLabel").pack(side=tk.LEFT, padx=(0, 5))
        self.port_var = tk.StringVar()
        self.port_combo = ttk.Combobox(inner, textvariable=self.port_var, width=22,
                                        style="Dark.TCombobox")
        self.port_combo.pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(inner, text="Refresh", style="Accent.TButton",
                   command=self._refresh_ports).pack(side=tk.LEFT, padx=(0, 10))

        ttk.Label(inner, text="Baud:", style="Panel.TLabel").pack(side=tk.LEFT, padx=(0, 5))
        self.baud_var = tk.StringVar(value="115200")
        tk.Entry(inner, textvariable=self.baud_var, width=8,
                 bg=BG_ENTRY, fg=FG_TEXT, font=FONT_MONO_SM,
                 insertbackground=FG_TEXT, relief=tk.FLAT).pack(side=tk.LEFT, padx=(0, 10))

        self.connect_btn = ttk.Button(inner, text="Conectar", style="Green.TButton",
                                       command=self._toggle_connection)
        self.connect_btn.pack(side=tk.LEFT)

        # Contenido principal: panel izquierdo + derecho
        main = ttk.Frame(self.root, style="Dark.TFrame")
        main.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)

        left = ttk.Frame(main, style="Dark.TFrame", width=310)
        left.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 5))
        left.pack_propagate(False)

        self._build_program_section(left)
        self._build_execution_section(left)
        self._build_debug_section(left)
        self._build_memory_section(left)

        right = ttk.Frame(main, style="Dark.TFrame")
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.notebook = ttk.Notebook(right)
        self.notebook.pack(fill=tk.BOTH, expand=True)

        # Tab: Editor
        self.editor_frame = ttk.Frame(self.notebook, style="Dark.TFrame")
        self.notebook.add(self.editor_frame, text=" Editor ")
        self._build_editor_tab()

        # Tab: Log
        self.log_frame = ttk.Frame(self.notebook, style="Dark.TFrame")
        self.notebook.add(self.log_frame, text=" Log ")
        self.log_text = scrolledtext.ScrolledText(
            self.log_frame, bg=BG_PANEL, fg=FG_TEXT, font=FONT_MONO_SM,
            insertbackground=FG_TEXT, relief=tk.FLAT, wrap=tk.WORD, state=tk.DISABLED
        )
        self.log_text.pack(fill=tk.BOTH, expand=True, padx=2, pady=2)
        self.log_text.tag_configure("info",    foreground=FG_TEXT)
        self.log_text.tag_configure("success", foreground=FG_GREEN)
        self.log_text.tag_configure("warning", foreground=FG_YELLOW)
        self.log_text.tag_configure("error",   foreground=FG_RED)
        self.log_text.tag_configure("accent",  foreground=FG_ACCENT)
        self.log_text.tag_configure("header",  foreground=FG_CYAN, font=FONT_MONO_LG)

        # Tab: Estado (Registros + Latches en una sola vista)
        self.estado_frame = ttk.Frame(self.notebook, style="Dark.TFrame")
        self.notebook.add(self.estado_frame, text=" Estado ")
        self._build_estado_tab()

        # Tab: Memoria
        self.mem_frame = ttk.Frame(self.notebook, style="Dark.TFrame")
        self.notebook.add(self.mem_frame, text=" Memoria ")
        self._build_mem_table()

        # Tab: Programa
        self.prog_frame = ttk.Frame(self.notebook, style="Dark.TFrame")
        self.notebook.add(self.prog_frame, text=" Programa ")
        self._build_prog_view()

    # --------------------------------------------------------
    # Panel izquierdo
    # --------------------------------------------------------
    def _build_program_section(self, parent):
        frame = ttk.LabelFrame(parent, text=" Programa ", style="Dark.TLabelframe")
        frame.pack(fill=tk.X, padx=5, pady=(0, 5))

        inner = ttk.Frame(frame, style="Panel.TFrame")
        inner.pack(fill=tk.X, padx=8, pady=8)

        self.file_var = tk.StringVar(value="(ninguno)")
        ttk.Label(inner, textvariable=self.file_var, style="Panel.TLabel").pack(fill=tk.X)

        row = ttk.Frame(inner, style="Panel.TFrame")
        row.pack(fill=tk.X, pady=(5, 0))

        ttk.Button(row, text="Cargar en FPGA", style="Green.TButton",
                   command=self._assemble_and_load).pack(fill=tk.X)

    def _build_execution_section(self, parent):
        frame = ttk.LabelFrame(parent, text=" Ejecucion ", style="Dark.TLabelframe")
        frame.pack(fill=tk.X, padx=5, pady=(0, 5))

        inner = ttk.Frame(frame, style="Panel.TFrame")
        inner.pack(fill=tk.X, padx=8, pady=8)

        row = ttk.Frame(inner, style="Panel.TFrame")
        row.pack(fill=tk.X, pady=(0, 5))
        ttk.Button(row, text=" Run ",   style="Green.TButton", command=self._run).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(row, text=" Step ",  style="Warn.TButton",  command=self._step).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(row, text=" Reset ", style="Red.TButton",   command=self._reset).pack(side=tk.LEFT)

        self.pc_var = tk.StringVar(value="PC: ---")
        ttk.Label(inner, textvariable=self.pc_var, style="Panel.TLabel",
                  font=FONT_MONO_LG).pack(fill=tk.X, pady=(3, 0))

    def _build_debug_section(self, parent):
        frame = ttk.LabelFrame(parent, text=" Debug ", style="Dark.TLabelframe")
        frame.pack(fill=tk.X, padx=5, pady=(0, 5))

        inner = ttk.Frame(frame, style="Panel.TFrame")
        inner.pack(fill=tk.X, padx=8, pady=8)

        row1 = ttk.Frame(inner, style="Panel.TFrame")
        row1.pack(fill=tk.X, pady=(0, 4))
        ttk.Button(row1, text="Regs",    style="Accent.TButton", command=self._read_regs).pack(side=tk.LEFT, padx=(0, 3))
        ttk.Button(row1, text="Latches", style="Accent.TButton", command=self._read_latches).pack(side=tk.LEFT, padx=(0, 3))
        ttk.Button(row1, text="PC",      style="Accent.TButton", command=self._read_pc).pack(side=tk.LEFT)

        ttk.Button(inner, text="Refresh All (Regs + Latches + PC)",
                   style="Green.TButton", command=self._refresh_all).pack(fill=tk.X)

    def _build_memory_section(self, parent):
        frame = ttk.LabelFrame(parent, text=" Memoria de Datos ", style="Dark.TLabelframe")
        frame.pack(fill=tk.X, padx=5, pady=(0, 5))

        inner = ttk.Frame(frame, style="Panel.TFrame")
        inner.pack(fill=tk.X, padx=8, pady=8)

        row = ttk.Frame(inner, style="Panel.TFrame")
        row.pack(fill=tk.X)

        ttk.Label(row, text="Addr:", style="Panel.TLabel").pack(side=tk.LEFT, padx=(0, 3))
        self.mem_addr_var = tk.StringVar(value="0")
        tk.Entry(row, textvariable=self.mem_addr_var, width=8,
                 bg=BG_ENTRY, fg=FG_TEXT, font=FONT_MONO_SM,
                 insertbackground=FG_TEXT, relief=tk.FLAT).pack(side=tk.LEFT, padx=(0, 8))

        ttk.Label(row, text="Len:", style="Panel.TLabel").pack(side=tk.LEFT, padx=(0, 3))
        self.mem_len_var = tk.StringVar(value="8")
        tk.Entry(row, textvariable=self.mem_len_var, width=6,
                 bg=BG_ENTRY, fg=FG_TEXT, font=FONT_MONO_SM,
                 insertbackground=FG_TEXT, relief=tk.FLAT).pack(side=tk.LEFT, padx=(0, 8))

        ttk.Button(row, text="Leer Mem", style="Accent.TButton",
                   command=self._read_mem).pack(side=tk.LEFT)

    # --------------------------------------------------------
    # Tab Editor
    # --------------------------------------------------------
    def _build_editor_tab(self):
        toolbar = ttk.Frame(self.editor_frame, style="Panel.TFrame")
        toolbar.pack(fill=tk.X, padx=2, pady=(2, 0))

        ttk.Button(toolbar, text="Nuevo",         style="Accent.TButton", command=self._editor_new).pack(side=tk.LEFT, padx=(2, 2), pady=4)
        ttk.Button(toolbar, text="Abrir",         style="Accent.TButton", command=self._open_file).pack(side=tk.LEFT, padx=(0, 2), pady=4)
        ttk.Button(toolbar, text="Guardar",       style="Accent.TButton", command=self._save_file).pack(side=tk.LEFT, padx=(0, 2), pady=4)
        ttk.Button(toolbar, text="Guardar Como",  style="Accent.TButton", command=self._save_file_as).pack(side=tk.LEFT, padx=(0, 10), pady=4)

        ttk.Label(toolbar, text="|", style="Dim.TLabel").pack(side=tk.LEFT, padx=4)

        ttk.Button(toolbar, text="Ensamblar",           style="Warn.TButton",  command=self._assemble).pack(side=tk.LEFT, padx=(4, 2), pady=4)
        ttk.Button(toolbar, text="Ensamblar y Cargar",  style="Green.TButton", command=self._assemble_and_load).pack(side=tk.LEFT, padx=(0, 2), pady=4)

        self.editor_file_label = ttk.Label(toolbar, text="sin archivo", style="Dim.TLabel")
        self.editor_file_label.pack(side=tk.RIGHT, padx=8)

        self.editor = scrolledtext.ScrolledText(
            self.editor_frame,
            bg=BG_EDITOR, fg=FG_TEXT, font=FONT_MONO,
            insertbackground=FG_CYAN,
            relief=tk.FLAT,
            wrap=tk.NONE,
            undo=True,
        )
        self.editor.pack(fill=tk.BOTH, expand=True, padx=2, pady=2)

        self.editor.tag_configure("keyword",  foreground=FG_CYAN)
        self.editor.tag_configure("register", foreground=FG_GREEN)
        self.editor.tag_configure("comment",  foreground=FG_DIM)
        self.editor.tag_configure("label",    foreground=FG_YELLOW)
        self.editor.tag_configure("number",   foreground=FG_ACCENT)

        self.editor.bind("<KeyRelease>", self._on_editor_change)

    def _on_editor_change(self, event=None):
        self._editor_modified = True
        # Debounce: resaltar 250ms despues de que el usuario deje de escribir
        if self._highlight_after_id:
            self.root.after_cancel(self._highlight_after_id)
        self._highlight_after_id = self.root.after(250, self._apply_syntax_highlight)

    def _apply_syntax_highlight(self):
        content = self.editor.get("1.0", tk.END)
        for tag in ("keyword", "register", "comment", "label", "number"):
            self.editor.tag_remove(tag, "1.0", tk.END)

        for lineno, raw_line in enumerate(content.split("\n")):
            row = lineno + 1
            line = raw_line

            # Comentarios (# o //)
            for marker in ("#", "//"):
                idx = line.find(marker)
                if idx >= 0:
                    self.editor.tag_add("comment", f"{row}.{idx}", f"{row}.end")
                    line = line[:idx]
                    break

            # Label (palabra seguida de :)
            m = re.match(r'^(\s*)(\w+)\s*:', line)
            if m:
                self.editor.tag_add("label", f"{row}.{m.start(2)}", f"{row}.{m.end(2)}")

            # Keywords (instrucciones)
            for kw in self._asm_keywords:
                for m in re.finditer(r'\b' + kw + r'\b', line, re.IGNORECASE):
                    self.editor.tag_add("keyword", f"{row}.{m.start()}", f"{row}.{m.end()}")

            # Registros
            for reg in self._asm_registers:
                for m in re.finditer(r'\b' + reg + r'\b', line, re.IGNORECASE):
                    self.editor.tag_add("register", f"{row}.{m.start()}", f"{row}.{m.end()}")

            # Numeros (hex y decimal)
            for m in re.finditer(r'\b(0x[0-9a-fA-F]+|-?\d+)\b', line):
                self.editor.tag_add("number", f"{row}.{m.start()}", f"{row}.{m.end()}")

    # --------------------------------------------------------
    # Tablas de datos
    # --------------------------------------------------------
    def _build_estado_tab(self):
        """Vista combinada: registros a la izquierda, latches a la derecha."""
        paned = ttk.PanedWindow(self.estado_frame, orient=tk.HORIZONTAL)
        paned.pack(fill=tk.BOTH, expand=True, padx=2, pady=2)

        # --- Panel izquierdo: registros ---
        regs_pane = ttk.Frame(paned, style="Dark.TFrame")
        paned.add(regs_pane, weight=1)

        ttk.Label(regs_pane, text="Registros",
                  style="Title.TLabel").pack(anchor=tk.W, padx=4, pady=(2, 0))

        regs_inner = ttk.Frame(regs_pane, style="Dark.TFrame")
        regs_inner.pack(fill=tk.BOTH, expand=True)

        cols = ("reg", "abi", "hex", "decimal")
        self.regs_tree = ttk.Treeview(regs_inner, columns=cols, show="headings",
                                       style="Reg.Treeview", height=32)
        self.regs_tree.heading("reg",     text="Reg")
        self.regs_tree.heading("abi",     text="ABI")
        self.regs_tree.heading("hex",     text="Hex")
        self.regs_tree.heading("decimal", text="Decimal")

        self.regs_tree.column("reg",     width=55,  anchor=tk.CENTER)
        self.regs_tree.column("abi",     width=55,  anchor=tk.CENTER)
        self.regs_tree.column("hex",     width=100, anchor=tk.CENTER)
        self.regs_tree.column("decimal", width=100, anchor=tk.CENTER)

        sb_regs = ttk.Scrollbar(regs_inner, orient=tk.VERTICAL, command=self.regs_tree.yview)
        self.regs_tree.configure(yscrollcommand=sb_regs.set)
        self.regs_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=2, pady=2)
        sb_regs.pack(side=tk.RIGHT, fill=tk.Y, pady=2)

        for i in range(32):
            self.regs_tree.insert("", tk.END, iid=f"r{i}",
                                   values=(f"x{i}", REG_ABI[i], "0x00000000", "0"))

        # --- Panel derecho: latches ---
        latches_pane = ttk.Frame(paned, style="Dark.TFrame")
        paned.add(latches_pane, weight=1)

        ttk.Label(latches_pane, text="Latches inter-etapa",
                  style="Title.TLabel").pack(anchor=tk.W, padx=4, pady=(2, 0))

        self.latches_text = scrolledtext.ScrolledText(
            latches_pane, bg=BG_PANEL, fg=FG_TEXT, font=FONT_MONO_SM,
            insertbackground=FG_TEXT, relief=tk.FLAT, wrap=tk.WORD, state=tk.DISABLED
        )
        self.latches_text.pack(fill=tk.BOTH, expand=True, padx=2, pady=2)
        self.latches_text.tag_configure("stage",   foreground=FG_CYAN, font=FONT_MONO_LG)
        self.latches_text.tag_configure("field",   foreground=FG_GREEN)
        self.latches_text.tag_configure("value",   foreground=FG_YELLOW)
        self.latches_text.tag_configure("decimal", foreground=FG_DIM)

    def _build_mem_table(self):
        cols = ("addr", "hex", "decimal")
        self.mem_tree = ttk.Treeview(self.mem_frame, columns=cols, show="headings",
                                      style="Reg.Treeview")
        self.mem_tree.heading("addr",    text="Direccion")
        self.mem_tree.heading("hex",     text="Hex")
        self.mem_tree.heading("decimal", text="Decimal")

        self.mem_tree.column("addr",    width=100, anchor=tk.CENTER)
        self.mem_tree.column("hex",     width=120, anchor=tk.CENTER)
        self.mem_tree.column("decimal", width=120, anchor=tk.CENTER)

        sb = ttk.Scrollbar(self.mem_frame, orient=tk.VERTICAL, command=self.mem_tree.yview)
        self.mem_tree.configure(yscrollcommand=sb.set)
        self.mem_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=2, pady=2)
        sb.pack(side=tk.RIGHT, fill=tk.Y, pady=2)

    def _build_prog_view(self):
        top = ttk.Frame(self.prog_frame, style="Dark.TFrame")
        top.pack(fill=tk.X, padx=5, pady=5)
        self.prog_info_var = tk.StringVar(value="Ningun programa cargado")
        ttk.Label(top, textvariable=self.prog_info_var, style="Dark.TLabel").pack(side=tk.LEFT)

        cols = ("addr", "hex", "asm")
        self.prog_tree = ttk.Treeview(self.prog_frame, columns=cols, show="headings",
                                       style="Reg.Treeview")
        self.prog_tree.heading("addr", text="Direccion")
        self.prog_tree.heading("hex",  text="Machine Code")
        self.prog_tree.heading("asm",  text="Assembly")

        self.prog_tree.column("addr", width=80,  anchor=tk.CENTER)
        self.prog_tree.column("hex",  width=120, anchor=tk.CENTER)
        self.prog_tree.column("asm",  width=300, anchor=tk.W)

        # Tag para resaltar instruccion en el PC actual
        self.prog_tree.tag_configure("current_pc", background="#44447a", foreground=FG_YELLOW)

        sb = ttk.Scrollbar(self.prog_frame, orient=tk.VERTICAL, command=self.prog_tree.yview)
        self.prog_tree.configure(yscrollcommand=sb.set)
        self.prog_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=2, pady=2)
        sb.pack(side=tk.RIGHT, fill=tk.Y, pady=2)

    # --------------------------------------------------------
    # Logging
    # --------------------------------------------------------
    def log(self, message, tag="info"):
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.insert(tk.END, message + "\n", tag)
        self.log_text.see(tk.END)
        self.log_text.configure(state=tk.DISABLED)

    # --------------------------------------------------------
    # Conexion
    # --------------------------------------------------------
    def _refresh_ports(self):
        ports = list(serial.tools.list_ports.comports())
        port_names = [f"{p.device} - {p.description}" for p in ports]
        self.port_combo["values"] = port_names
        if port_names:
            selected = 0
            for i, p in enumerate(ports):
                desc  = (p.description  or "").lower()
                manuf = (p.manufacturer or "").lower()
                if any(kw in desc  for kw in ["ftdi", "digilent", "uart", "usb serial"]):
                    selected = i; break
                if any(kw in manuf for kw in ["ftdi", "digilent"]):
                    selected = i; break
            self.port_combo.current(selected)

    def _toggle_connection(self):
        if self.connected:
            self._disconnect()
        else:
            self._connect()

    def _connect(self):
        port_str = self.port_var.get()
        if not port_str:
            messagebox.showwarning("Sin puerto", "Seleccionar un puerto serial.")
            return
        port = port_str.split(" - ")[0].strip()
        try:
            baud = int(self.baud_var.get())
        except ValueError:
            messagebox.showerror("Baud rate invalido", "Ingresar un numero valido.")
            return
        try:
            self.dbg = FPGADebugger(port, baud, timeout=5)
            self.connected = True
            self.connect_btn.configure(text="Desconectar", style="Red.TButton")
            self.status_label.configure(text=f"  Conectado: {port} @ {baud}", foreground=FG_GREEN)
            self.log(f"Conectado a {port} @ {baud} baud", "success")
        except Exception as e:
            messagebox.showerror("Error de conexion", str(e))
            self.log(f"Error al conectar: {e}", "error")

    def _disconnect(self):
        if self.dbg:
            self.dbg.close()
            self.dbg = None
        self.connected = False
        self.connect_btn.configure(text="Conectar", style="Green.TButton")
        self.status_label.configure(text="  Desconectado", foreground=FG_RED)
        self.log("Desconectado.", "warning")

    def _require_connection(self):
        if not self.connected or not self.dbg:
            messagebox.showwarning("Sin conexion", "Conectar a la FPGA primero.")
            return False
        return True

    # --------------------------------------------------------
    # Editor
    # --------------------------------------------------------
    def _editor_new(self):
        if self._editor_modified:
            if not messagebox.askyesno("Nuevo archivo", "¿Descartar cambios no guardados?"):
                return
        self.editor.delete("1.0", tk.END)
        self._current_file = None
        self._editor_modified = False
        self.file_var.set("(ninguno)")
        self.editor_file_label.configure(text="sin archivo")
        self.log("Editor: nuevo archivo.")

    def _open_file(self):
        filepath = filedialog.askopenfilename(
            title="Abrir archivo assembly",
            filetypes=[("Assembly RISC-V", "*.asm *.s"), ("Todos", "*.*")],
            initialdir=os.path.dirname(os.path.abspath(__file__))
        )
        if not filepath:
            return
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            self.editor.delete("1.0", tk.END)
            self.editor.insert("1.0", content)
            self._current_file = filepath
            self._editor_modified = False
            basename = os.path.basename(filepath)
            self.file_var.set(basename)
            self.editor_file_label.configure(text=basename)
            self.log(f"Archivo abierto: {filepath}")
            self._apply_syntax_highlight()
            self.notebook.select(self.editor_frame)
        except Exception as e:
            self.log(f"Error al abrir archivo: {e}", "error")
            messagebox.showerror("Error", str(e))

    def _save_file(self):
        if not self._current_file:
            self._save_file_as()
            return
        try:
            content = self.editor.get("1.0", tk.END)
            with open(self._current_file, 'w', encoding='utf-8') as f:
                f.write(content)
            self._editor_modified = False
            self.log(f"Archivo guardado: {self._current_file}", "success")
        except Exception as e:
            self.log(f"Error al guardar: {e}", "error")
            messagebox.showerror("Error", str(e))

    def _save_file_as(self):
        init_dir = (os.path.dirname(self._current_file)
                    if self._current_file else os.path.dirname(os.path.abspath(__file__)))
        filepath = filedialog.asksaveasfilename(
            title="Guardar archivo assembly",
            defaultextension=".asm",
            filetypes=[("Assembly RISC-V", "*.asm *.s"), ("Todos", "*.*")],
            initialdir=init_dir
        )
        if not filepath:
            return
        self._current_file = filepath
        basename = os.path.basename(filepath)
        self.file_var.set(basename)
        self.editor_file_label.configure(text=basename)
        self._save_file()

    # --------------------------------------------------------
    # Programa
    # --------------------------------------------------------
    def _assemble(self):
        source = self.editor.get("1.0", tk.END).strip()
        if not source:
            messagebox.showwarning("Editor vacio", "Escribir o cargar codigo assembly primero.")
            return None

        try:
            words = self.asm.assemble(source)
            self.loaded_program = words
            # Usar self.asm.instructions para mapeo correcto (sin labels sueltos ni comentarios)
            instructions = self.asm.instructions  # [(addr_bytes, line_str), ...]
            self.log(f"Ensamblado exitoso: {len(words)} instrucciones", "success")

            self.prog_tree.delete(*self.prog_tree.get_children())
            for i, (addr, asm_line) in enumerate(instructions):
                self.prog_tree.insert("", tk.END, iid=f"prog_{addr}",
                                      values=(f"0x{addr:04X}", f"0x{words[i]:08X}", asm_line))

            self.prog_info_var.set(f"{len(words)} instrucciones ensambladas")
            self.notebook.select(self.prog_frame)
            return words

        except Exception as e:
            self.log(f"Error de ensamblado: {e}", "error")
            messagebox.showerror("Error de ensamblado", str(e))
            return None

    def _assemble_and_load(self):
        words = self._assemble()
        if words is not None:
            self._load_program()

    def _load_program(self):
        if not self._require_connection():
            return
        if self.loaded_program is None:
            if self._assemble() is None:
                return

        def task():
            with self._serial_lock:
                try:
                    self.log(f"Cargando {len(self.loaded_program)} instrucciones...", "accent")
                    self.dbg.load_program(self.loaded_program)
                    self.dbg.reset()
                    self.log("Programa cargado y pipeline reseteado.", "success")
                    self._update_pc_display()
                except Exception as e:
                    self.log(f"Error al cargar: {e}", "error")

        threading.Thread(target=task, daemon=True).start()

    # --------------------------------------------------------
    # Ejecucion
    # --------------------------------------------------------
    def _run(self):
        if not self._require_connection():
            return

        def task():
            with self._serial_lock:
                try:
                    # Reset previo: garantiza que cada Run empiece desde PC=0
                    # y evita que clicks sucesivos sigan avanzando el PC tras HALT.
                    self.dbg.reset()
                    time.sleep(0.1)
                    self.log("Ejecutando programa (modo continuo)...", "accent")
                    self.dbg.run()
                    time.sleep(0.5)
                    pc = self._update_pc_display()
                    self.log(f"Ejecucion finalizada. PC = 0x{pc:08X}" if pc is not None else "Ejecucion finalizada.", "success")
                    self._do_read_regs()
                    self._do_read_latches()
                except Exception as e:
                    self.log(f"Error: {e}", "error")

        threading.Thread(target=task, daemon=True).start()

    def _step(self):
        if not self._require_connection():
            return

        def task():
            with self._serial_lock:
                try:
                    self.dbg.step()
                    pc = self._update_pc_display()
                    self.log(f"Step -> PC = 0x{pc:08X}" if pc is not None else "Step ejecutado.", "warning")
                    self._do_read_regs()
                    self._do_read_latches()
                except Exception as e:
                    self.log(f"Error: {e}", "error")

        threading.Thread(target=task, daemon=True).start()

    def _reset(self):
        if not self._require_connection():
            return

        def task():
            with self._serial_lock:
                try:
                    self.dbg.reset()
                    self._update_pc_display()
                    self.log("Pipeline reseteado.", "success")
                except Exception as e:
                    self.log(f"Error: {e}", "error")

        threading.Thread(target=task, daemon=True).start()

    def _update_pc_display(self):
        """Lee PC, actualiza label y resalta en tab Programa. Retorna el PC leido."""
        try:
            pc = self.dbg.get_pc()
            self.root.after(0, lambda: self.pc_var.set(f"PC: 0x{pc:08X}  ({pc})"))
            self.root.after(0, lambda: self._highlight_pc_in_program(pc))
            return pc
        except Exception:
            self.root.after(0, lambda: self.pc_var.set("PC: error"))
            return None

    def _highlight_pc_in_program(self, pc):
        """Resalta la instruccion correspondiente al PC en el tab Programa."""
        for iid in self.prog_tree.get_children():
            self.prog_tree.item(iid, tags=())
        target = f"prog_{pc}"
        if self.prog_tree.exists(target):
            self.prog_tree.item(target, tags=("current_pc",))
            self.prog_tree.see(target)

    # --------------------------------------------------------
    # Debug reads
    # --------------------------------------------------------
    def _do_read_regs(self):
        """Lee registros y actualiza tabla. Asume que el lock serial esta tomado."""
        try:
            regs = self.dbg.get_regs()
            self.root.after(0, lambda: self._update_regs_table(regs))
            self.log("Registros leidos.", "success")
        except Exception as e:
            self.log(f"Error al leer registros: {e}", "error")

    def _do_read_latches(self):
        """Lee latches y actualiza display. Asume que el lock serial esta tomado."""
        try:
            latches = self.dbg.get_latches()
            self.root.after(0, lambda: self._update_latches_display(latches))
            self.log("Latches leidos.", "success")
        except Exception as e:
            self.log(f"Error al leer latches: {e}", "error")

    def _read_regs(self):
        if not self._require_connection():
            return

        def task():
            with self._serial_lock:
                self._do_read_regs()
            self.root.after(0, lambda: self.notebook.select(self.estado_frame))

        threading.Thread(target=task, daemon=True).start()

    def _update_regs_table(self, regs):
        for i in range(32):
            val = regs[i]
            signed = val if val < 0x80000000 else val - 0x100000000
            self.regs_tree.item(f"r{i}", values=(f"x{i}", REG_ABI[i], f"0x{val:08X}", str(signed)))

    def _read_latches(self):
        if not self._require_connection():
            return

        def task():
            with self._serial_lock:
                self._do_read_latches()
            self.root.after(0, lambda: self.notebook.select(self.estado_frame))

        threading.Thread(target=task, daemon=True).start()

    def _update_latches_display(self, latches):
        self.latches_text.configure(state=tk.NORMAL)
        self.latches_text.delete("1.0", tk.END)

        for stage_name, fields in latches.items():
            self.latches_text.insert(tk.END, f"\n {'='*46}\n", "stage")
            self.latches_text.insert(tk.END, f"  Latch {stage_name}\n", "stage")
            self.latches_text.insert(tk.END, f" {'='*46}\n\n", "stage")
            for fname, fval in fields.items():
                signed = fval if fval < 0x80000000 else fval - 0x100000000
                self.latches_text.insert(tk.END, f"  {fname:<18}", "field")
                self.latches_text.insert(tk.END, f"0x{fval:08X}", "value")
                self.latches_text.insert(tk.END, f"  ({signed})\n", "decimal")

        self.latches_text.configure(state=tk.DISABLED)

    def _read_pc(self):
        if not self._require_connection():
            return

        def task():
            with self._serial_lock:
                try:
                    pc = self.dbg.get_pc()
                    self.root.after(0, lambda: self.pc_var.set(f"PC: 0x{pc:08X}  ({pc})"))
                    self.root.after(0, lambda: self._highlight_pc_in_program(pc))
                    self.log(f"PC = 0x{pc:08X} ({pc})", "success")
                except Exception as e:
                    self.log(f"Error al leer PC: {e}", "error")

        threading.Thread(target=task, daemon=True).start()

    def _refresh_all(self):
        """Lee PC + registros + latches en un solo click."""
        if not self._require_connection():
            return

        def task():
            with self._serial_lock:
                try:
                    self.log("Refresh All...", "accent")
                    self._update_pc_display()
                    self._do_read_regs()
                    self._do_read_latches()
                    self.log("Refresh All completo.", "success")
                    self.root.after(0, lambda: self.notebook.select(self.estado_frame))
                except Exception as e:
                    self.log(f"Error en Refresh All: {e}", "error")

        threading.Thread(target=task, daemon=True).start()

    # --------------------------------------------------------
    # Memoria
    # --------------------------------------------------------
    def _read_mem(self):
        if not self._require_connection():
            return
        try:
            addr   = int(self.mem_addr_var.get(), 0)
            length = int(self.mem_len_var.get(), 0)
        except ValueError:
            messagebox.showerror("Error", "Direccion o longitud invalida. Usar hex (0x...) o decimal.")
            return

        def task():
            with self._serial_lock:
                try:
                    words = self.dbg.get_mem(addr, length)
                    self.root.after(0, lambda: self._update_mem_table(words, addr))
                    self.log(f"Memoria leida: {length} words desde 0x{addr:04X}", "success")
                    self.root.after(0, lambda: self.notebook.select(self.mem_frame))
                except Exception as e:
                    self.log(f"Error al leer memoria: {e}", "error")

        threading.Thread(target=task, daemon=True).start()

    def _update_mem_table(self, words, base_addr):
        self.mem_tree.delete(*self.mem_tree.get_children())
        for i, w in enumerate(words):
            addr   = base_addr + i * 4
            signed = w if w < 0x80000000 else w - 0x100000000
            self.mem_tree.insert("", tk.END,
                                  values=(f"0x{addr:04X}", f"0x{w:08X}", str(signed)))


# ============================================================
# Main
# ============================================================
def main():
    root = tk.Tk()
    try:
        root.iconbitmap(default="")
    except Exception:
        pass
    RISCVDebuggerGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
