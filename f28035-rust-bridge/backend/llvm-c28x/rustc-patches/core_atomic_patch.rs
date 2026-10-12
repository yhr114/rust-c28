// C28x core atomic policy
//
// Do not add target-specific Atomic* implementations backed by ordinary
// volatile loads and stores. Such operations are not atomic with respect to
// interrupts and would violate Rust's memory model, especially for
// read-modify-write and compare_exchange.
//
// The rustc target sets:
//
//     max_atomic_width: Some(0),
//     atomic_cas: false,
//
// This makes core omit unsupported atomic integer APIs. Peripheral and
// scheduler code must use an interrupt-masking critical-section primitive.
// Atomics can be enabled later only after LLVM has correct lowering for loads,
// stores, fences, and interrupt-safe read-modify-write operations.
