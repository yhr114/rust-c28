	.global	f_i16_i32                       ; -- Begin function f_i16_i32
	.p2align	1
f_i16_i32:                              ; @f_i16_i32
	.cfi_startproc
; %bb.0:
	addb sp, #1
	movl xar7, acc
	mov al, ar7
	movz ar7, al
	mov al, ar4
	add al, ar7
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_i32_i16                       ; -- Begin function f_i32_i16
	.p2align	1
f_i32_i16:                              ; @f_i32_i16
	.cfi_startproc
; %bb.0:
	addb sp, #3
	movz ar0, ar4
	movl xar7, acc
	movl acc, xar0
	movl xt, acc
	movl acc, xar7
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #3
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #3
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #3
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_i16_i16_i32                   ; -- Begin function f_i16_i16_i32
	.p2align	1
f_i16_i16_i32:                          ; @f_i16_i16_i32
	.cfi_startproc
; %bb.0:
	addb sp, #1
	movl xar7, acc
	mov ah, ar7
	mov al, ar4
	add al, ar5
	add al, ah
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_i32_i16_i16                   ; -- Begin function f_i32_i16_i16
	.p2align	1
f_i32_i16_i16:                          ; @f_i32_i16_i16
	.cfi_startproc
; %bb.0:
	addb sp, #5
	movz ar1, ar4
	movz ar0, ar5
	movl xar7, acc
	movl acc, xar1
	movl xt, acc
	movl acc, xar7
	addl acc, xt
	movl xar1, acc
	movz ar7, sp
	subb xar7, #3
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #3
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	movl acc, xar0
	movl xt, acc
	movl acc, xar7
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #5
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #5
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #5
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_i16_i32_i16                   ; -- Begin function f_i16_i32_i16
	.p2align	1
f_i16_i32_i16:                          ; @f_i16_i32_i16
	.cfi_startproc
; %bb.0:
	addb sp, #1
	movl xar7, acc
	mov al, ar7
	movz ar7, al
	mov al, ar4
	add al, ar7
	add al, ar5
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_i32_i32                       ; -- Begin function f_i32_i32
	.p2align	1
f_i32_i32:                              ; @f_i32_i32
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
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #3
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #3
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #5
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_i16_i32_i32                   ; -- Begin function f_i16_i32_i32
	.p2align	1
f_i16_i32_i32:                          ; @f_i16_i32_i32
	.cfi_startproc
; %bb.0:
	addb sp, #7
	movz ar7, sp
	subb xar7, #11
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
	movz ar0, ar4
	movl xar7, acc
	addl acc, xt
	movl xar1, acc
	movz ar7, sp
	subb xar7, #3
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #3
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	movl acc, xar0
	movl xt, acc
	movl acc, xar7
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #5
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #5
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #7
	lretr
	.cfi_endproc
                                        ; -- End function
