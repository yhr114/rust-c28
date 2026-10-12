# pie_irq_single_source

A minimal PIE/interrupt testcase using CPU Timer0 as one clean interrupt source.

Purpose:

- confirm the PIE vector remap path works
- confirm Group1/INT7 can reach software ISR
- confirm basic interrupt ack flow works
- provide the first real PIE single-source pass/fail case
