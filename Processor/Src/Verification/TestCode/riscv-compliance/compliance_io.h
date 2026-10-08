#ifndef RSD_COMPLIANCE_IO_H
#define RSD_COMPLIANCE_IO_H

// The driver validates the complete signature against the upstream reference.
// Suppress diagnostic macros, as in the previous RSD target.
#define RVTEST_IO_INIT
#define RVTEST_IO_CHECK()
#define RVTEST_IO_WRITE_STR(_STR)
#define RVTEST_IO_ASSERT_GPR_EQ(_R, _I)
#define RVTEST_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVTEST_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#endif // RSD_COMPLIANCE_IO_H
