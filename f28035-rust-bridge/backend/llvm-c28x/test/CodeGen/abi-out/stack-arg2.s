	.global	caller                          ; -- Begin function caller
	.p2align	1
caller:                                 ; @caller
	.cfi_startproc
; %bb.0:
	push ar4
	push ar5
	addb sp, #3
	addb sp, #1
	mov al, #5
	movz ar7, sp
	subb xar7, #1
	mov *xar7, al
	mov al, #1
	mov ah, #2
	mov ar4, #3
	mov ar5, #4
	lcr callee
	subb sp, #1
	subb sp, #3
	pop ar5
	pop ar4
	lretr
	.cfi_endproc
                                        ; -- End function
