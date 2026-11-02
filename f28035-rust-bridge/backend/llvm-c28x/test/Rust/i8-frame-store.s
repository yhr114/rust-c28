	.global	i8_frame_store                  ; -- Begin function i8_frame_store
	.p2align	1
i8_frame_store:                         ; @i8_frame_store
	.cfi_startproc
; %bb.0:                                ; %entry
	addb sp, #2
	movl xar0, acc
	movz ar7, sp
	subb xar7, #2
	movl acc, xar7
	setc c
	rol acc
	movl xar7, acc
	movl xar1, xar7
	mov al, ar4
	push ar0
	push acc
	movl acc, xar1
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
	mov al, ar4
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
	subb sp, #2
	lretr
	.cfi_endproc
                                        ; -- End function
	.global	i8_two_slots                    ; -- Begin function i8_two_slots
	.p2align	1
i8_two_slots:                           ; @i8_two_slots
	.cfi_startproc
; %bb.0:                                ; %entry
	addb sp, #2
	movl xar0, acc
	movz ar7, sp
	subb xar7, #2
	movl acc, xar7
	clrc c
	rol acc
	movl xar7, acc
	movl xar1, xar7
	mov al, ar4
	push ar0
	push acc
	movl acc, xar1
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
	movz ar7, sp
	subb xar7, #2
	movl acc, xar7
	setc c
	rol acc
	movl xar7, acc
	movl xar1, xar7
	mov al, ar5
	push ar0
	push acc
	movl acc, xar1
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
	mov al, ar5
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
	subb sp, #2
	lretr
	.cfi_endproc
                                        ; -- End function
