target triple = "c28x-ti-none"

; 0x1000000 = 2^24 exceeds the 22-bit field of MOVL XARn,#22bit
; (0x3FFFFF is the largest encodable word address).
;
; Must be rejected during instruction selection by the imm22 value predicate in
; C28xInstrFormats.td, NOT silently truncated to 22 bits by the encoder.  A
; truncated address would point at a completely different peripheral register,
; which is exactly the class of bug a fail-closed backend exists to prevent.
define i16 @out_of_range_address() {
entry:
  %v = load volatile i16, ptr inttoptr (i32 16777216 to ptr), align 2
  ret i16 %v
}
