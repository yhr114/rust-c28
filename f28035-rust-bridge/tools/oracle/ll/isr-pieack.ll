; 契约 fixture：ISR 形状（写 GPIO + PIEACK + LRETR）
; 镜像 PATH A rust_timer0_interrupt 已验证序列（control-loop.asm 第 186-194 行）：
;   ... GPIO 写 ...
;   MOV @PieCtrlRegs+1, #1     ; PIEACK 清零（c28x-rt 中断 ABI 的一部分）
;   LRETR
; 属契约型用例。
define void @timer0_isr() {
entry:
  store volatile i16 -32768, i16* inttoptr (i32 0x6F0E to i16*), align 2
  store volatile i16 1, i16* inttoptr (i32 0x0CE1 to i16*), align 2
  ret void
}
