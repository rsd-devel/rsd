#ifndef RSD_COMPLIANCE_IO_H
#define RSD_COMPLIANCE_IO_H

#if 0
    // Output string
    #define RVTEST_IO_WRITE_STR(_STR) RSD_IO_WRITE_STR(_STR)

    // Check results
    #define RVTEST_IO_ASSERT_GPR_EQ(_R, _I) \
        li t0, _I ;\
        beq _R, t0, 20000f ;\
        RSD_IO_WRITE_STR("Assertion violation: file ") ;\
        RSD_IO_WRITE_STR(__FILE__)               ;\
        RSD_IO_WRITE_STR(", line ")              ;\
        RSD_IO_WRITE_STR(RSD_TOSTRING(__LINE__))     ;\
        RSD_IO_WRITE_STR(": ")                   ;\
        RSD_IO_WRITE_STR(# _R)                   ;\
        RSD_IO_WRITE_STR("(")                    ;\
        RSD_IO_WRITE_GPR(_R)                      ;\
        RSD_IO_WRITE_STR(") != ")                ;\
        RSD_IO_WRITE_STR(# _I)                   ;\
        RSD_IO_WRITE_STR("\n")                   ;\
    20000:  ;\
    
#else 
    // Output string
    #define RVTEST_IO_WRITE_STR(_STR)

    // Check results
    #define RVTEST_IO_ASSERT_GPR_EQ(_R, _I)
#endif


#define RVTEST_IO_INIT
#define RVTEST_IO_CHECK()
#define RVTEST_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVTEST_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#endif // RSD_COMPLIANCE_IO_H
