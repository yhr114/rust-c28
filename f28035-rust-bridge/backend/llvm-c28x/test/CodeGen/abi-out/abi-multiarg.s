	.global	f2                              ; -- Begin function f2
	.p2align	1
f2:                                     ; @f2
	.cfi_startproc
; %bb.0:
	addb sp, #1
	add al, ah
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f3                              ; -- Begin function f3
	.p2align	1
f3:                                     ; @f3
	.cfi_startproc
; %bb.0:
	addb sp, #1
	add al, ah
	add al, ar4
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f4                              ; -- Begin function f4
	.p2align	1
f4:                                     ; @f4
	.cfi_startproc
; %bb.0:
	addb sp, #1
	add al, ah
	mov ah, ar4
	add ah, ar5
	add al, ah
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	f1_32                           ; -- Begin function f1_32
	.p2align	1
f1_32:                                  ; @f1_32
	.cfi_startproc
; %bb.0:
	addb sp, #3
	movl xar7, acc
	movl xt, acc
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
	.global	f2_32                           ; -- Begin function f2_32
	.p2align	1
f2_32:                                  ; @f2_32
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
