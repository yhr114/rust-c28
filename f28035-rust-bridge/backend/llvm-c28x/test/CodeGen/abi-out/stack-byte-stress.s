	.global	large_local_frame               ; -- Begin function large_local_frame
	.p2align	1
large_local_frame:                      ; @large_local_frame
; %bb.0:                                ; %entry
	addb sp, #127
	addb sp, #127
	addb sp, #3
	movz ar7, sp
	subb xar7, #2
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
	pop acc
	mov *xar7, al
	movl acc, xar0
	clrc c
	ror acc
	movl xar7, acc
	mov al, *xar7
	subb sp, #127
	subb sp, #127
	subb sp, #3
	lretr
                                        ; -- End function
	.global	many_live_i32                   ; -- Begin function many_live_i32
	.p2align	1
many_live_i32:                          ; @many_live_i32
; %bb.0:                                ; %entry
	addb sp, #53
	movz ar7, sp
	subb xar7, #69
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
	subb xar7, #67
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
	subb xar7, #13
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar7, sp
	subb xar7, #65
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
	subb xar7, #63
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
	subb xar7, #9
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar7, sp
	subb xar7, #61
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
	subb xar7, #59
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
	subb xar7, #5
	push acc
	movl acc, xt
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	pop acc
	movz ar7, sp
	subb xar7, #57
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
	subb xar7, #17
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
	movl xar1, acc
	movz ar7, sp
	subb xar7, #35
	movl acc, xar1
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
	movl xar1, acc
	movz ar7, sp
	subb xar7, #15
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #35
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #17
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push ar0
	movl acc, xar0
	mov ar0, ah
	xor ah, ar0
	push acc
	movl acc, xar0
	mov ar0, al
	pop acc
	xor al, ar0
	pop ar0
	movz ar7, sp
	subb xar7, #15
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	push acc
	movl acc, xt
	push ar0
	movl acc, xar0
	mov ar0, ah
	xor ah, ar0
	push acc
	movl acc, xar0
	mov ar0, al
	pop acc
	xor al, ar0
	pop ar0
	movl xt, acc
	pop acc
	movz ar7, sp
	subb xar7, #17
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	movl xar7, acc
	addl acc, xt
	movl xar1, acc
	movz ar7, sp
	subb xar7, #19
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #19
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	mov al, ar7
	movz ar7, sp
	subb xar7, #29
	mov *xar7, al
	mov ah, #0
	push acc
	mov t, al
	mpyu acc, t, ah
	movl xar1, acc
	pop acc
	movz ar7, sp
	subb xar7, #23
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #19
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar1, #16
	push acc
	movl xar7, xar1
	mov t, ar7
	lsrl acc,t
	movl xar2, acc
	pop acc
	movz ar7, sp
	subb xar7, #21
	movl acc, xar2
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #21
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	mov al, ar7
	mov ah, #17
	movz ar7, sp
	subb xar7, #28
	mov *xar7, ah
	push acc
	mov t, al
	mpyu acc, t, ah
	movl xar2, acc
	pop acc
	movz ar7, sp
	subb xar7, #25
	movl acc, xar2
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
	subb xar7, #25
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar2, acc
	movz ar7, sp
	subb xar7, #27
	movl acc, xar2
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #27
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push acc
	movl xar7, xar1
	mov t, ar7
	lsl acc,t
	movl xar1, acc
	pop acc
	movz ar7, sp
	subb xar7, #31
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #28
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #29
	mov al, *xar7
	push acc
	mov t, al
	mpyu acc, t, ah
	movl xar1, acc
	pop acc
	movz ar7, sp
	subb xar7, #33
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #31
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #33
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar7, acc
	addl acc, xt
	movl xar1, acc
	movz ar7, sp
	subb xar7, #37
	movl acc, xar1
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #35
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xt, acc
	movz ar7, sp
	subb xar7, #37
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	push ar0
	movl acc, xar0
	mov ar0, ah
	xor ah, ar0
	push acc
	movl acc, xar0
	mov ar0, al
	pop acc
	xor al, ar0
	pop ar0
	movl xar7, acc
	addl acc, xt
	movl xar0, acc
	movz ar7, sp
	subb xar7, #39
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #39
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	subb sp, #53
	lretr
                                        ; -- End function
	.global	packed_byte_store               ; -- Begin function packed_byte_store
	.p2align	1
packed_byte_store:                      ; @packed_byte_store
; %bb.0:                                ; %entry
	addb sp, #5
	movz ar7, sp
	subb xar7, #2
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #3
	mov *xar7, al
	push acc
	movl xar0, #packed
	movl acc, xar0
	clrc c
	rol acc
	movl xar0, acc
	pop acc
	push acc
	movl acc, xar0
	add acc, #4
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #5
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	movz ar7, sp
	subb xar7, #2
	mov ah, *xar7
	movz ar7, sp
	subb xar7, #3
	mov al, *xar7
	push ar0
	movl xar7, #packed
	mov ar0, #1
	movb *+xar7[ar0], al
	pop ar0
	movz ar7, sp
	subb xar7, #5
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	mov al, ah
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
	subb sp, #5
	lretr
                                        ; -- End function
	.global	packed_byte_sum                 ; -- Begin function packed_byte_sum
	.p2align	1
packed_byte_sum:                        ; @packed_byte_sum
; %bb.0:                                ; %entry
	addb sp, #3
	movl xar0, #packed
	movl acc, xar0
	clrc c
	rol acc
	movl xar0, acc
	push acc
	movl acc, xar0
	add acc, #4
	movl xar0, acc
	pop acc
	movz ar7, sp
	subb xar7, #3
	movl acc, xar0
	mov *xar7, al
	addb xar7, #1
	mov *xar7, ah
	push ar0
	movl xar7, #packed
	mov ar0, #1
	movb al, *+xar7[ar0]
	mov ar7, al
	pop ar0
	mov al, ar7
	movz ar7, sp
	subb xar7, #3
	mov al, *xar7
	addb xar7, #1
	mov ah, *xar7
	movl xar0, acc
	push acc
	push ar0
	movl acc, xar0
	movl xar7, acc
	mov ar0, #1
	and al, ar0
	mov ar0, al
	movl acc, xar7
	clrc c
	ror acc
	movl xar7, acc
	movb al, *+xar7[ar0]
	mov ar7, al
	pop ar0
	pop acc
	mov ah, ar7
	add al, ah
	subb sp, #3
	lretr
                                        ; -- End function
	.global	packed                          ; @packed
	.p2align	1, 0x0
packed:
	.space	6

