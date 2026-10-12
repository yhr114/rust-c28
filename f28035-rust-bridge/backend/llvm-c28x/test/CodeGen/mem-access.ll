; mem-access.ll —访存行为回归测试（ABI L1-1 字节地址模型）
;
; 覆盖：
;   1. 双字节数组低/高字节读写（MOVB lane 选择，地址奇偶性）
;   2. i8 栈变量 alloca/store/load（奇数偏移帧索引，ACC 保护）
;   3. i32 store/load（相邻两字，AL 低字 AH 高字）
;   4. GR32 指针寄存器溢出（多指针变量迫使 XAR 入栈/出栈）
;
; 所有指针均为逻辑字节地址；16/32 位访存前由后端转换为字地址。

target triple = "c28x-ti-none"

; 2-byte global array.  byte0 = [0] (low byte, even addr), byte1 = [1] (high byte, odd addr).
@bytes2 = global [2 x i8] zeroinitializer, align 1

; 32-bit global (two adjacent 16-bit words).
@val32 = global i32 0, align 4

; === 1. 双字节数组低/高字节 ===

; store_byte0(v): write v to bytes2[0] (low byte — even byte address).
define void @store_byte0(i8 %v) nounwind {
  store i8 %v, ptr @bytes2
  ret void
}

; load_byte0(): read bytes2[0] (low byte).
define i8 @load_byte0() nounwind {
  %v = load i8, ptr @bytes2
  ret i8 %v
}

; store_byte1(v): write v to bytes2[1] (high byte — odd byte address).
define void @store_byte1(i8 %v) nounwind {
  %p = getelementptr [2 x i8], ptr @bytes2, i32 0, i32 1
  store i8 %v, ptr %p
  ret void
}

; load_byte1(): read bytes2[1] and return it.
define i8 @load_byte1() nounwind {
  %p = getelementptr [2 x i8], ptr @bytes2, i32 0, i32 1
  %v = load i8, ptr %p
  ret i8 %v
}

; === 2. i8 栈变量 ===

; i8_stack(a, b): alloca i8, store a, load back, add b, return.
define i8 @i8_stack(i8 %a, i8 %b) nounwind {
  %x = alloca i8, align 1
  store i8 %a, ptr %x
  %y = load i8, ptr %x
  %sum = add i8 %y, %b
  ret i8 %sum
}

; === 3. i32 store/load ===

; i32_store(v): write 32-bit v to global val32 (two adjacent words).
define void @i32_store(i32 %v) nounwind {
  store i32 %v, ptr @val32
  ret void
}

; i32_load(): read 32-bit from global val32.
define i32 @i32_load() nounwind {
  %v = load i32, ptr @val32
  ret i32 %v
}

; === 4. (GR32/ACCOnly 溢出路径已在 store/loadRegToStackSlot 实现) ===
; 多 i32 活值溢出需要寄存器分配器进一步集成，留待后续。
