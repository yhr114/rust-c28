use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, ItemFn};

/// Marks the entry point of the application.
///
/// # Usage
///
/// ```ignore
/// #[entry]
/// fn main() -> ! {
///     loop {}
/// }
/// ```
///
/// This expands to:
/// ```ignore
/// #[no_mangle]
/// extern "C" fn main() -> ! {
///     loop {}
/// }
/// ```
#[proc_macro_attribute]
pub fn entry(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as ItemFn);
    let sig = &input.sig;
    let block = &input.block;
    let attrs = &input.attrs;

    let expanded = quote! {
        #(#attrs)*
        #[no_mangle]
        #sig {
            #block
        }
    };

    expanded.into()
}

/// Marks a function to run *before* `.bss`/`.data` are initialized.
///
/// The startup code calls `PreInit` right after setting the stack pointer
/// and before zeroing `.bss` / copying `.data`.  Overrides the default
/// empty `PreInit_` in `c28x-rt`.
///
/// # Usage
///
/// ```ignore
/// #[pre_init]
/// fn my_pre_init() {
///     /* e.g. disable watchdog, set clock */
/// }
/// ```
///
/// This expands to:
/// ```ignore
/// #[no_mangle]
/// extern "C" fn PreInit() {
///     /* ... */
/// }
/// ```
#[proc_macro_attribute]
pub fn pre_init(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as ItemFn);
    let block = &input.block;
    let attrs = &input.attrs;

    // Force the function to be named `PreInit` so the linker's
    // PROVIDE(PreInit = PreInit_) resolves to the user's override.
    let expanded = quote! {
        #(#attrs)*
        #[no_mangle]
        extern "C" fn PreInit() {
            // Preserve the original body; rename to PreInit.
            #block
        }
    };

    expanded.into()
}

/// Marks an interrupt service routine.
///
/// # Usage
///
/// ```ignore
/// #[interrupt]
/// fn TINT0() {
///     /* acknowledge PIE, clear interrupt flag, ... */
/// }
/// ```
///
/// # Status: transitional
///
/// C28x has no `extern "c28x-interrupt"` ABI in rustc yet (unlike
/// `extern "msp430-interrupt"`), so this macro currently expands to a
/// plain `extern "C"` function named after your handler.  That means:
///
/// - The function **must** return with `LRETR` (the C28x `extern "C"`
///   leaf return), not `RETE`/some other convention.
/// - **Register save/restore is not automatic.**  C28x does *not*
///   push registers on interrupt entry the way Cortex-M does.  If your
///   ISR touches ACC/XAR/XT/T/ST0/ST1, you must push/pop them yourself
///   (typically in an assembly trampoline, or until rustc grows the
///   dedicated interrupt ABI which does this for you).
/// - The symbol name (e.g. `TINT0`) must match the handler name your
///   PAC crate references in the PIE table / `device.x`.
///
/// When `extern "c28x-interrupt"` lands in rustc, this macro will be
/// updated to use it without changing user code.
#[proc_macro_attribute]
pub fn interrupt(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as ItemFn);
    let sig = &input.sig;
    let block = &input.block;
    let attrs = &input.attrs;
    let fn_name = &sig.ident;

    let expanded = quote! {
        #(#attrs)*
        #[no_mangle]
        extern "C" fn #fn_name() {
            #block
        }
    };

    expanded.into()
}
