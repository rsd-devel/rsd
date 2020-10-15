    .file    "code.s"
    .option nopic
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li    a4, 0xFFFFFFFF
    j     main2
end:
    j     end
end2:
    j     end
main2:
    addi  a7, a7, 1
    jal   a1, main3
end3:
    j     end
main3:
    addi  a7, a7, 1
    beq   a1, a2, end
    beq   a2, a3, main4
end4:
    j     end
main4:
    addi  a7, a7, 1
    bne   a2, a3, end
    bne   a1, a2, main5
end5:
    j     end
main5:
    addi  a7, a7, 1
    blt   a2, a3, end
    blt   a0, a4, end
    blt   a4, a0, main6
end6:
    j     end
main6:
    addi  a7, a7, 1
    bge   a4, a0, end
    bge   a0, a4, main7
end7:
    j     end
main7:
    addi  a7, a7, 1
    bge   a2, a3, main8
end8:
    j     end
main8:
    addi  a7, a7, 1
    bltu  a2, a3, end
    bltu  a4, a0, end
    bltu  a0, a4, main9
end9:
    j     end
main9:
    addi  a7, a7, 1
    bgeu  a0, a4, end
    bgeu  a4, a0, main10
end10:
    j     end
main10:
    addi  a7, a7, 1
    bgeu  a2, a3, main11
end11:
    j     end
main11:
    li    a1, 0
    #j     main11
    ret
