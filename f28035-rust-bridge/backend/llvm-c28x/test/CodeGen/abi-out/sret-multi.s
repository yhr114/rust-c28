	.global	mk                              ; -- Begin function mk
	.p2align	1
mk:                                     ; @mk
	.cfi_startproc
; %bb.0:
	addb sp, #5
	movz ar7, sp
	subb xar7, #9
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
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	pop acc
	movz ar7, sp
	subb xar7, #3
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
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
	subb xar7, #3
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
	.global	use1                            ; -- Begin function use1
	.p2align	1
use1:                                   ; @use1
	.cfi_startproc
; %bb.0:
	push ar6
	addb sp, #15
	movz ar7, sp
	subb xar7, #6
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #20
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar0, xar7
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #4
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movl xar0, #16
	push acc
	movl xar7, xar0
	mov t, ar7
	lsrl acc,t
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #4
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #6
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, xar0
	mov ar0, ar7
	addb sp, #2
	movz ar7, sp
	subb xar7, #1
	mov *xar7, ar0
	push acc
	movl acc, xt
	movl xar7, acc
	pop acc
	mov ar0, ar7
	movz ar7, sp
	subb xar7, #2
	mov *xar7, ar0
	movz ar7, sp
	subb xar7, #14
	push acc
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar6, xar7
	pop acc
	movz ar7, sp
	subb xar7, #10
	push acc
	movl acc, xar6
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	lcr mk
	movz ar7, sp
	subb xar7, #10
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	subb sp, #2
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #15
	pop ar6
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	use2                            ; -- Begin function use2
	.p2align	1
use2:                                   ; @use2
	.cfi_startproc
; %bb.0:
	push ar6
	addb sp, #13
	movz ar7, sp
	subb xar7, #6
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #18
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar0, xar7
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #4
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movl xar0, #16
	push acc
	movl xar7, xar0
	mov t, ar7
	lsrl acc,t
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #4
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #6
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, xar0
	mov ar0, ar7
	addb sp, #2
	movz ar7, sp
	subb xar7, #1
	mov *xar7, ar0
	push acc
	movl acc, xt
	movl xar7, acc
	pop acc
	mov ar0, ar7
	movz ar7, sp
	subb xar7, #2
	mov *xar7, ar0
	movz ar7, sp
	subb xar7, #12
	push acc
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar6, xar7
	pop acc
	lcr mk
	subb sp, #2
	movz ar7, sp
	subb xar7, #8
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar0, xar7
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #13
	pop ar6
	lretr
	.cfi_endproc
                                        ; -- End function
