	.global	caller                          ; -- Begin function caller
	.p2align	1
caller:                                 ; @caller
	.cfi_startproc
; %bb.0:
	addb sp, #2
	movz ar7, sp
	subb xar7, #5
	push acc
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar0, xar7
	pop acc
	push acc
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	mov ar7, al
	pop acc
	mov ar0, ar7
	addb sp, #1
	movz ar7, sp
	subb xar7, #1
	mov *xar7, ar0
	lcr callee
	subb sp, #1
	subb sp, #2
	lretr
	.cfi_endproc
                                        ; -- End function
