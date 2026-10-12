# safe_hal_control_loop

Safe HAL integration bridge case for ADC + ePWM1 + Timer0 + GPIO.

Run:

```powershell
.\tools\verify-safe-hal-case-ram.ps1 -Case integration/safe_hal_control_loop
```

The app case is tracked in `app/hardware-tests`, while the target object comes
from `crates/rust-api::application::rust_main` lowered through `backend/c28x-mir`.
