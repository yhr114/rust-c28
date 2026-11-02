	.global	many                            ; -- Begin function many
	.p2align	1
many:                                   ; @many
	.cfi_startproc
; %bb.0:
	push ar4
	push ar5
	addb sp, #3
	addb sp, #3
	mov ah, #5
	movz ar7, sp
	subb xar7, #1
	mov *xar7, ah
	mov ah, #6
	movz ar7, sp
	subb xar7, #2
	mov *xar7, ah
	mov ah, #7
	movz ar7, sp
	subb xar7, #3
	mov *xar7, ah
	mov ah, #2
	mov ar4, #3
	mov ar5, #4
	lcr sum
	subb sp, #3
	subb sp, #3
	pop ar5
	pop ar4
	lretr
	.cfi_endproc
                                        ; -- End function
