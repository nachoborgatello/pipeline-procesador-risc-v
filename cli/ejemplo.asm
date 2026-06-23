# Programa de prueba RISC-V
# Suma simple: x3 = x1 + x2

addi x1, x0, 5       # x1 = 5
addi x2, x0, 10      # x2 = 10
add  x3, x1, x2      # x3 = 15
sw   x3, 0(x0)        # mem[0] = 15
lw   x4, 0(x0)        # x4 = mem[0] = 15
halt

