/*
  OoO test: MUL takes 4 cycles, independent ADDIs should execute during that time.
  Expected: x3=100, x4=200, x5=300, x6=112 (=12+100)
*/
    li  x1, 3
    li  x2, 4
    mul x10, x1, x2    # x10 = 12, occupies MULT FU for 4 cycles
    addi x3, x0, 100   # independent, should execute while mul is in-flight
    addi x4, x0, 200   # independent
    addi x5, x0, 300   # independent
    add  x6, x10, x3   # depends on x10, must wait for mul to complete
    wfi
