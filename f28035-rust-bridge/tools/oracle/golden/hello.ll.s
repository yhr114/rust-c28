; CONTRACT GOLDEN — hello.ll（define i16 @add(i16 %lhs, i16 %rhs)）
; 形状由 PATH A / C28x ISA 推导；精确寄存器分配待 llc 输出后锁定。
; 触发检查：add, lretr
add:
	add $dst, $lhs, $rhs
	lretr
