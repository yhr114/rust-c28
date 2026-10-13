	.global	caller                          ; -- Begin function caller
	.p2align	1
caller:                                 ; @caller
	.cfi_startproc
; %bb.0:
	lcr callee
	lretr
	.cfi_endproc
                                        ; -- End function
