	.global	bb_stack                        ; -- Begin function bb_stack
	.p2align	1
bb_stack:                               ; @bb_stack
	.cfi_startproc
; %bb.0:                                ; %entry
	addb sp, #29
	movz ar7, sp
	subb xar7, #15
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #34
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
	mov al, ar7
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
	mov ar7, al
	pop acc
	mov ah, ar7
	movz ar7, sp
	subb xar7, #32
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
	movz ar1, ar4
	movl xt, xar1
	movz ar7, sp
	subb xar7, #17
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar1, ar5
	movl xt, xar1
	movz ar7, sp
	subb xar7, #19
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar0, ar0
	movl xt, xar0
	movz ar7, sp
	subb xar7, #21
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar0, ah
	movl xt, xar0
	movz ar7, sp
	subb xar7, #23
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar0, al
	movl acc, xar0
	movz ar7, sp
	subb xar7, #25
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	mov al, #1
	movz ar7, al
	mov al, ar4
	and al, ar7
	mov ah, #0
	cmp al, ah
	b LBB0_2, eq
	b LBB0_1, unc
LBB0_1:                                 ; %then
	movz ar7, sp
	subb xar7, #25
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #15
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #11
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #11
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #13
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	b LBB0_3, unc
LBB0_2:                                 ; %else
	movz ar7, sp
	subb xar7, #17
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #15
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
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
	subb xar7, #9
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #13
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	b LBB0_3, unc
LBB0_3:                                 ; %join
	movz ar7, sp
	subb xar7, #19
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
	subb xar7, #3
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #21
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #3
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
	subb xar7, #23
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
	subb sp, #29
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	inner                           ; -- Begin function inner
	.p2align	1
inner:                                  ; @inner
	.cfi_startproc
; %bb.0:
	addb sp, #9
	movz ar7, sp
	subb xar7, #14
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
	movz ar1, ar4
	movz ar0, ar0
	movl xar7, xar1
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
	subb sp, #9
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	outer                           ; -- Begin function outer
	.p2align	1
outer:                                  ; @outer
	.cfi_startproc
; %bb.0:                                ; %entry
	push ar6
	addb sp, #33
	movz ar7, sp
	subb xar7, #22
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #38
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
	mov ar1, ar7
	movz ar7, sp
	subb xar7, #37
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
	mov ar2, ar7
	movz ar7, sp
	subb xar7, #39
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
	movz ar7, sp
	subb xar7, #20
	mov *xar7, ar0
	movz ar3, ar4
	movz ar6, ar0
	movl xar7, acc
	mov al, ar7
	movz ar7, sp
	subb xar7, #14
	mov *xar7, al
	mov ah, #0
	push acc
	mov t, al
	mpyu acc, t, ah
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #6
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #22
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, #16
	movz ar7, sp
	subb xar7, #10
	push acc
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	push acc
	movl xar7, xar0
	mov t, ar7
	lsrl acc,t
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #4
	movl acc, xar0
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
	mov ah, #3
	movz ar7, sp
	subb xar7, #13
	mov *xar7, ah
	push acc
	mov t, al
	mpyu acc, t, ah
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #8
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #6
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #8
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #12
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #10
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	movz ar7, sp
	subb xar7, #12
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push acc
	movl xar7, xar0
	mov t, ar7
	lsl acc,t
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #16
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #13
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #14
	mov al, *xar7
	push acc
	mov t, al
	mpyu acc, t, ah
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #18
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #16
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #18
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #26
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #20
	mov al, *xar7
	mov ar7, al
	mov ar0, ar7
	movl xar7, xar3
	movl acc, xar6
	movl xt, acc
	movl acc, xar7
	addl acc, xt
	movl xar3, acc
	movz ar7, sp
	subb xar7, #24
	movl acc, xar3
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #22
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	addb sp, #3
	movz ar7, sp
	subb xar7, #1
	mov *xar7, ar2
	movz ar7, sp
	subb xar7, #2
	mov *xar7, ar1
	movz ar7, sp
	subb xar7, #3
	mov *xar7, ar0
	lcr inner
	subb sp, #3
	movl xt, acc
	movz ar7, sp
	subb xar7, #24
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #28
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #26
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #28
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #30
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #30
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #33
	pop ar6
	lretr
	.cfi_endproc
                                        ; -- End function
