; 契约 fixture：寄存器字 RMW（打包字节模型的基础形状）
; 镜像 PATH A c28x_mir_periodic_start 已验证序列（control-loop.asm 第 242-247 行）：
;   MOVL XAR4, #0x0C04
;   MOV AL, *XAR4
;   MOV AH, #0
;   AND ACC, #0xFFEF
;   OR  ACC, #0x0010
;   MOV *XAR4, AL
; 属契约型用例。
define void @byte_rmw(i16 %bit) {
entry:
  %r = load volatile i16, i16* inttoptr (i32 0x0C04 to i16*), align 2
  %c = and i16 %r, -17
  %s = or i16 %c, %bit
  store volatile i16 %s, i16* inttoptr (i32 0x0C04 to i16*), align 2
  ret void
}
