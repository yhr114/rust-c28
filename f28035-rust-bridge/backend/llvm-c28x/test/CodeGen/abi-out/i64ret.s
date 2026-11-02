	.global	ret_i64                         ; -- Begin function ret_i64
	.p2align	1
ret_i64:                                ; @ret_i64
	.cfi_startproc
; %bb.0:
	addb sp, #5
	movz ar7, sp
	subb xar7, #3
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movl xar0, #31
	push acc
	movl xar7, xar0
	mov t, ar7
	asrl acc,t
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #5
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #3
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push acc
	movl acc, xar6
	clrc c
	ror acc
	movl xar7, acc
	pop acc
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	push acc
	movl acc, xar6
	add acc, #4
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #5
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push acc
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	pop acc
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	subb sp, #5
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	use_i64                         ; -- Begin function use_i64
	.p2align	1
use_i64:                                ; @use_i64
	.cfi_startproc
; %bb.0:
	push ar6
	addb sp, #9
	movz ar7, sp
	subb xar7, #8
	push acc
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar6, xar7
	pop acc
	movz ar7, sp
	subb xar7, #4
	push acc
	movl acc, xar6
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	lcr ret_i64
	movz ar7, sp
	subb xar7, #4
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #9
	pop ar6
	lretr
	.cfi_endproc
                                        ; -- End function
