	.global	make_wide                       ; -- Begin function make_wide
	.p2align	1
make_wide:                              ; @make_wide
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
	.global	use_wide                        ; -- Begin function use_wide
	.p2align	1
use_wide:                               ; @use_wide
	.cfi_startproc
; %bb.0:
	push ar6
	addb sp, #17
	movz ar7, sp
	subb xar7, #6
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #22
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
	subb xar7, #16
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
	lcr make_wide
	movz ar7, sp
	subb xar7, #10
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	subb sp, #2
	movz ar7, sp
	subb xar7, #12
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar1, xar7
	movl acc, xar1
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movl acc, xar0
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
	subb xar7, #10
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #10
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #17
	pop ar6
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	many                            ; -- Begin function many
	.p2align	1
many:                                   ; @many
	.cfi_startproc
; %bb.0:
	addb sp, #23
	movz ar7, sp
	subb xar7, #33
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
	subb xar7, #11
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar7, sp
	subb xar7, #31
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
	subb xar7, #7
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar7, sp
	subb xar7, #29
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
	movz ar7, sp
	subb xar7, #27
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
	subb xar7, #9
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #7
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #9
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #13
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #11
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #13
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #15
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #15
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #23
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	call_many                       ; -- Begin function call_many
	.p2align	1
call_many:                              ; @call_many
	.cfi_startproc
; %bb.0:
	addb sp, #1
	addb sp, #8
	mov al, #0
	movz ar7, sp
	subb xar7, #1
	mov *xar7, al
	mov ah, #2
	movz ar7, sp
	subb xar7, #2
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #3
	mov *xar7, al
	mov ah, #3
	movz ar7, sp
	subb xar7, #4
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #5
	mov *xar7, al
	mov ah, #4
	movz ar7, sp
	subb xar7, #6
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #7
	mov *xar7, al
	mov al, #5
	movz ar7, sp
	subb xar7, #8
	mov *xar7, al
	movl xar0, #1
	movl acc, xar0
	lcr many
	subb sp, #8
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	wide_mul                        ; -- Begin function wide_mul
	.p2align	1
wide_mul:                               ; @wide_mul
	.cfi_startproc
; %bb.0:
	push ar6
	addb sp, #23
	movz ar7, sp
	subb xar7, #8
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #28
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
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #10
	push acc
	movl acc, xar6
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movl xar1, #31
	push acc
	movl xar7, xar1
	mov t, ar7
	asrl acc,t
	movl xar2, acc
	pop acc
	movz ar7, sp
	subb xar7, #4
	movl acc, xar2
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	push acc
	movl xar7, xar1
	mov t, ar7
	movl acc, xar0
	asrl acc,t
	movl xar1, acc
	pop acc
	movz ar7, sp
	subb xar7, #6
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #4
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	mov al, ar7
	addb sp, #6
	movz ar7, sp
	subb xar7, #1
	mov *xar7, al
	movz ar7, sp
	subb xar7, #2
	mov *xar7, al
	movl xar1, #16
	push acc
	movl xar7, xar1
	mov t, ar7
	movl acc, xar0
	lsrl acc,t
	movl xar1, acc
	pop acc
	movz ar7, sp
	subb xar7, #12
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #14
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, xar1
	mov ar1, ar7
	movz ar7, sp
	subb xar7, #3
	mov *xar7, ar1
	movl xar7, xar0
	mov ar0, ar7
	movz ar7, sp
	subb xar7, #4
	mov *xar7, ar0
	push acc
	movl acc, xt
	movl xar7, acc
	pop acc
	mov ar0, ar7
	movz ar7, sp
	subb xar7, #5
	mov *xar7, ar0
	movz ar7, sp
	subb xar7, #6
	mov *xar7, ar0
	movz ar7, sp
	subb xar7, #26
	push acc
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar6, xar7
	pop acc
	movz ar7, sp
	subb xar7, #18
	push acc
	movl acc, xar6
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	lcr __muldi3
	movz ar7, sp
	subb xar7, #16
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar6, acc
	movz ar7, sp
	subb xar7, #18
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	subb sp, #6
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #16
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
	subb xar7, #14
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	push acc
	movl acc, xar6
	add acc, #4
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #14
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #16
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push acc
	movl acc, xt
	push acc
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	pop acc
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
	subb sp, #23
	pop ar6
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	use_widemul                     ; -- Begin function use_widemul
	.p2align	1
use_widemul:                            ; @use_widemul
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
	lcr wide_mul
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
