; 契约 fixture：XAR4 间接寻址 MMIO 写
; 镜像 PATH A c28x_mir_upcount_apply 已验证序列（control-loop.asm 第 199-201 行）：
;   MOVL XAR4, #0x6800
;   MOVB AL, #0x0000
;   MOV *XAR4, AL
; 属契约型用例。
define void @xar_indirect_write(i16 %val) {
entry:
  store volatile i16 %val, i16* inttoptr (i32 0x6800 to i16*), align 2
  ret void
}
