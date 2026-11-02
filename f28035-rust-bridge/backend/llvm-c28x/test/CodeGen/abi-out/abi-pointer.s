	.global	f_ptr_i32                       ; -- Begin function f_ptr_i32
	.p2align	1
f_ptr_i32:                              ; @f_ptr_i32
	.cfi_startproc
; %bb.0:
	addb sp, #3
	movl xt, acc
	movl acc, xar4
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
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
	subb sp, #3
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_ptr_ptr                       ; -- Begin function f_ptr_ptr
	.p2align	1
f_ptr_ptr:                              ; @f_ptr_ptr
	.cfi_startproc
; %bb.0:
	addb sp, #3
	movl acc, xar4
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push acc
	movl acc, xar5
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
	subb sp, #3
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_ptr_i16                       ; -- Begin function f_ptr_i16
	.p2align	1
f_ptr_i16:                              ; @f_ptr_i16
	.cfi_startproc
; %bb.0:
	addb sp, #3
	movz ar0, al
	movl acc, xar4
	clrc c
	ror acc
	movl xar7, acc
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
	.global	f_i16_ptr_i32                   ; -- Begin function f_i16_ptr_i32
	.p2align	1
f_i16_ptr_i32:                          ; @f_i16_ptr_i32
	.cfi_startproc
; %bb.0:
	addb sp, #5
	movl xt, acc
	movz ar0, ar5
	movl acc, xar4
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
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
	subb sp, #5
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_3ptr                          ; -- Begin function f_3ptr
	.p2align	1
f_3ptr:                                 ; @f_3ptr
	.cfi_startproc
; %bb.0:
	addb sp, #9
	movz ar7, sp
	subb xar7, #13
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
	movl xar0, acc
	movl acc, xar4
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push acc
	movl acc, xar5
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	pop acc
	push acc
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #3
	push acc
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
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
	movl xt, acc
	movz ar7, sp
	subb xar7, #5
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #7
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #7
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #9
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_i32_ptr_i32                   ; -- Begin function f_i32_ptr_i32
	.p2align	1
f_i32_ptr_i32:                          ; @f_i32_ptr_i32
	.cfi_startproc
; %bb.0:
	addb sp, #9
	movl xt, acc
	movz ar7, sp
	subb xar7, #13
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
	subb xar7, #3
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movl acc, xar4
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
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
	movl xt, acc
	movz ar7, sp
	subb xar7, #5
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #7
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #7
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #9
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f_fnptr                         ; -- Begin function f_fnptr
	.p2align	1
f_fnptr:                                ; @f_fnptr
	.cfi_startproc
; %bb.0:
	addb sp, #1
	push acc
	movl acc, xar4
	clrc c
	ror acc
	movl xar7, acc
	pop acc
	lcr *xar7
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
