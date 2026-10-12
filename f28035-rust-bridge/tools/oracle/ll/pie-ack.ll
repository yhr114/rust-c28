; 契约 fixture：PIEACK 写（PieCtrlRegs.PIEACK = 0x0CE1）
; 镜像 PATH A c28x_mir_mmio_5 已验证序列（control-loop.asm 第 264-266 行）：
;   MOVL XAR4, #0x0CE1
;   MOVB AL, #0x0001
;   MOV *XAR4, AL
; 属契约型用例。
define void @pie_ack() {
entry:
  store volatile i16 1, i16* inttoptr (i32 0x0CE1 to i16*), align 2
  ret void
}
