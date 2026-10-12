# pie_mask_ack_basic

A minimal PIE mask/ack testcase using the CPU Timer0 interrupt path.

Purpose:

- confirm a Group1/INTx7 interrupt can be taken once
- confirm masking PIEIER1.INTx7 prevents the ISR from re-entering
- confirm re-enabling the source allows the interrupt path to recover

Note:

- this case stays on the same timer/PIE path as `pie_irq_single_source`
- it focuses on mask and recovery behavior, not complex nested interrupt usage
