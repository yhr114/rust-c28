use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, parse_quote, ItemFn, ReturnType, Type};

fn expand(kind: &str, attr: proc_macro2::TokenStream, mut f: ItemFn) -> syn::Result<proc_macro2::TokenStream> {
    if !attr.is_empty() { return Err(syn::Error::new_spanned(attr, "this attribute takes no arguments")); }
    let s = &f.sig;
    if s.constness.is_some() || s.asyncness.is_some() || s.abi.is_some() ||
        !s.generics.params.is_empty() || s.generics.where_clause.is_some() ||
        s.variadic.is_some() || !s.inputs.is_empty() || !matches!(f.vis, syn::Visibility::Inherited) {
        return Err(syn::Error::new_spanned(s, "expected a private, non-async, non-const, non-generic Rust fn with no arguments"));
    }
    if f.attrs.iter().any(|a| a.path().is_ident("no_mangle") || a.path().is_ident("export_name") || a.path().is_ident("unsafe")) {
        return Err(syn::Error::new_spanned(&f, "symbol export is owned by c28x-rt"));
    }
    let never = matches!(&s.output, ReturnType::Type(_, ty) if matches!(**ty, Type::Never(_)));
    let unit = matches!(&s.output, ReturnType::Default) ||
        matches!(&s.output, ReturnType::Type(_, ty) if matches!(&**ty, Type::Tuple(t) if t.elems.is_empty()));
    let symbol = match kind {
        "entry" => {
            if !never { return Err(syn::Error::new_spanned(&s.output, "#[entry] must return !")); }
            f.sig.abi = Some(parse_quote!(extern "C"));
            "main".to_owned()
        }
        "pre_init" => {
            if !unit || s.unsafety.is_none() { return Err(syn::Error::new_spanned(s, "#[pre_init] requires unsafe fn() (memory is not initialized yet)")); }
            f.sig.abi = Some(parse_quote!(extern "C"));
            "PreInit".to_owned()
        }
        "interrupt" => {
            if !unit && !never { return Err(syn::Error::new_spanned(&s.output, "#[interrupt] must return () or !")); }
            let name = s.ident.to_string();
            if !VECTORS.contains(&name.as_str()) { return Err(syn::Error::new_spanned(&s.ident, "unknown F28035 interrupt vector")); }
            f.sig.abi = Some(parse_quote!(extern "c28x-interrupt"));
            name
        }
        _ => unreachable!(),
    };
    Ok(quote! {
        #[allow(non_snake_case)]
        #[unsafe(export_name = #symbol)]
        #f
    })
}

/// Export `fn name() -> !` as the TI runtime's C ABI `main` entry.
#[proc_macro_attribute]
pub fn entry(attr: TokenStream, item: TokenStream) -> TokenStream {
    expand("entry", attr.into(), parse_macro_input!(item as ItemFn)).unwrap_or_else(syn::Error::into_compile_error).into()
}
/// Export `unsafe fn name()` as the hook before RAM initialization.
#[proc_macro_attribute]
pub fn pre_init(attr: TokenStream, item: TokenStream) -> TokenStream {
    expand("pre_init", attr.into(), parse_macro_input!(item as ItemFn)).unwrap_or_else(syn::Error::into_compile_error).into()
}
/// Bind a named F28035 vector using the compiler's c28x-interrupt ABI.
/// The application requires `#![feature(abi_c28x_interrupt)]`. Peripheral
/// interrupt flags and PIE acknowledgement remain the handler's responsibility.
#[proc_macro_attribute]
pub fn interrupt(attr: TokenStream, item: TokenStream) -> TokenStream {
    expand("interrupt", attr.into(), parse_macro_input!(item as ItemFn)).unwrap_or_else(syn::Error::into_compile_error).into()
}

// Names from the repository's TI DSP2803x_PieVect.h; reserved slots excluded.
const VECTORS: &[&str] = &[
    "TINT1","TINT2","DATALOG","RTOSINT","EMUINT","NMI","ILLEGAL",
    "USER1","USER2","USER3","USER4","USER5","USER6","USER7","USER8","USER9","USER10","USER11","USER12",
    "ADCINT1","ADCINT2","XINT1","XINT2","ADCINT9","TINT0","WAKEINT",
    "EPWM1_TZINT","EPWM2_TZINT","EPWM3_TZINT","EPWM4_TZINT","EPWM5_TZINT","EPWM6_TZINT","EPWM7_TZINT",
    "EPWM1_INT","EPWM2_INT","EPWM3_INT","EPWM4_INT","EPWM5_INT","EPWM6_INT","EPWM7_INT",
    "ECAP1_INT","HRCAP1_INT","HRCAP2_INT","EQEP1_INT","SPIRXINTA","SPITXINTA","SPIRXINTB","SPITXINTB",
    "I2CINT1A","I2CINT2A","SCIRXINTA","SCITXINTA","LIN0INTA","LIN1INTA","ECAN0INTA","ECAN1INTA",
    "ADCINT3","ADCINT4","ADCINT5","ADCINT6","ADCINT7","ADCINT8",
    "CLA1_INT1","CLA1_INT2","CLA1_INT3","CLA1_INT4","CLA1_INT5","CLA1_INT6","CLA1_INT7","CLA1_INT8","XINT3","LVF","LUF",
];

#[cfg(test)]
mod tests {
    use super::*;
    fn run(kind: &str, source: &str) -> syn::Result<proc_macro2::TokenStream> {
        expand(kind, quote!(), syn::parse_str(source).unwrap())
    }
    #[test]
    fn entry_and_preinit_contracts() {
        let t=run("entry","fn boot() -> ! { loop {} }").unwrap().to_string();
        assert!(t.contains("extern \"C\"")); assert!(t.contains("export_name = \"main\""));
        for s in ["fn boot() {}","fn boot(a:u16)->!{loop{}}","pub fn boot()->!{loop{}}","async fn boot()->!{loop{}}","fn boot<T>()->!{loop{}}"] { assert!(run("entry",s).is_err()); }
        assert!(run("pre_init","fn early() {}").is_err());
        assert!(run("pre_init","unsafe fn early() {}").unwrap().to_string().contains("PreInit"));
    }
    #[test]
    fn interrupt_uses_real_abi_and_rejects_typos() {
        let t=run("interrupt","fn TINT0() {}").unwrap().to_string();
        assert!(t.contains("extern \"c28x-interrupt\""));
        assert!(run("interrupt","fn TIMER0() {}").is_err());
        assert!(run("interrupt","fn TINT0(a:u16) {}").is_err());
        assert!(run("interrupt","fn TINT0()->u16 {0}").is_err());
    }
}