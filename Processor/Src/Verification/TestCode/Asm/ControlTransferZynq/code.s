    .file    "code.s"
    .text
    .align    2
    .globl    main
    .type     main, @function
main:
    li    a4, 0xFFFFFFFF    # 01. a4 <- -1
    li    a6, 0x40002000    # 02. a6 <- 0x40002000
    j     main2             # 03.
end:
    j     end
end2:
    j     end
main2:
    addi  a7, a7, 1         # 04. a7 <- 1
    jal   a1, main3         # 05. a1 <- PC, 
end3:
    j   end
main3:
    addi  a7, a7, 1         # 06. a7 <- 2
    beq   a1, a2, end       # 07. a1(2) != a2(0)
    beq   a2, a3, main4     # 08. a2(0) == a3(0) -> main4
end4:
    j     end
main4:
    addi  a7, a7, 1         # 09. a7 <- 3
    bne   a2, a3, end       # 10. a2(0) == a3(0)
    bne   a1, a2, main5     # 11. a1(x) != a2(0) -> main5
end5:
    j     end
main5:
    addi  a7, a7, 1         # 12. a7 <- 4
    blt   a2, a3, end       # 13. a2(0) >= a3(0)
    blt   a0, a4, end       # 14. a0(0) >= a4(-1)
    blt   a4, a0, main6     # 15. a4(-1) < a0(0) -> main6
end6:
    j     end
main6:
    addi  a7, a7, 1         # 16. a7 <- 5
    bge   a4, a0, end       # 17. a4(-1) < a0(0)
    bge   a0, a4, main7     # 18. a0(0) >= a4(-1) -> main7
end7:
    j     end
main7:
    addi  a7, a7, 1         # 19. a7 <- 6
    bge   a2, a3, main8     # 20. a2(0) >= a3(0) -> main8
end8:
    j     end
main8:
    addi  a7, a7, 1         # 21. a7(0) <- 7
    bltu  a2, a3, end       # 22. a2(0) == a3(0)
    bltu  a4, a0, end       # 23. a4(-1) > a0(0)
    bltu  a0, a4, main9     # 24. a0(0) < a4(-1) -> main9
end9:
    j     end
main9:
    addi  a7, a7, 1         # 25. a7 <- 8
    bgeu  a0, a4, end       # 26. a0(0) > a4(-1)
    bgeu  a4, a0, main10    # 27. -> main10
end10:
    j     end
main10:
    addi  a7, a7, 1         # 28. a7 <- 9
    bgeu  a2, a3, output    # 29 -> output
end11:
    j     end
output:
    li a1, 0
    ret
