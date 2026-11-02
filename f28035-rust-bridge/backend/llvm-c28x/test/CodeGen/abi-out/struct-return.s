	.global	make_pair                       ; -- Begin function make_pair
	.p2align	1
make_pair:                              ; @make_pair
	.cfi_startproc
; %bb.0:                                ; %entry
	addb sp, #1
	push acc
	movl acc, xar6
	clrc c
	ror acc
	movl xar7, acc
	pop acc
	mov *xar7, al
	push acc
	movl acc, xar6
	add acc, #2
	movl xar0, acc
	pop acc
	mov al, #17
	push ar0
	push acc
	movl acc, xar0
	movl xar7, acc
	mov ar0, #1
	and al, ar0
	mov ar0, al
	movl acc, xar7
	clrc c
	ror acc
	movl xar7, acc
	pop acc
	movb *+xar7[ar0], al
	pop ar0
	push acc
	movl acc, xar6
	add acc, #3
	movl xar0, acc
	pop acc
	mov al, #34
	push ar0
	push acc
	movl acc, xar0
	movl xar7, acc
	mov ar0, #1
	and al, ar0
	mov ar0, al
	movl acc, xar7
	clrc c
	ror acc
	movl xar7, acc
	pop acc
	movb *+xar7[ar0], al
	pop ar0
	subb sp, #1
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	use_pair                        ; -- Begin function use_pair
	.p2align	1
use_pair:                               ; @use_pair
	.cfi_startproc
; %bb.0:                                ; %entry
	push ar6
	addb sp, #2
	movl xar6, xar4
	mov al, #7
	mov ah, #9
	lcr make_pair
	subb sp, #2
	pop ar6
	lretr
	.cfi_endproc
                                        ; -- End function
