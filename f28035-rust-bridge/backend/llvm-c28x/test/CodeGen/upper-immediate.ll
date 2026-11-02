target triple = "c28x-ti-none"

; MOVL's upper six bits must be extracted before narrowing to 16 bits.
; 0x00050001 is the merged { enum tag=1, payload=5 } initialization.
define i32 @enum_tag_payload() { ret i32 327681 }
define i32 @upper_boundary() { ret i32 4194303 }
define i32 @upper_first_bit() { ret i32 65536 }
