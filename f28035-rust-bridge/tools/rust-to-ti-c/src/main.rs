use std::collections::BTreeMap;
use std::sync::OnceLock;

// Global variable-to-pin mapping: "led" -> 39, "button" -> 34, "adc0" -> 0
static VAR_PIN_MAP: OnceLock<std::sync::Mutex<BTreeMap<String, u16>>> = OnceLock::new();

fn var_pin_map() -> &'static std::sync::Mutex<BTreeMap<String, u16>> {
    VAR_PIN_MAP.get_or_init(|| std::sync::Mutex::new(BTreeMap::new()))
}
use std::env;
use std::fs;
use std::path::Path;

use syn::{
    BinOp, Expr, FnArg, ForeignItem, GenericArgument, Item, ItemFn, Lit, Pat, ReturnType, Stmt,
    Type, Visibility,
};

#[derive(Clone)]
struct ForeignSignature {
    parameters: usize,
    returns_u16: bool,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("rust-to-ti-c: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut arguments = env::args_os().skip(1);
    let input = arguments
        .next()
        .ok_or_else(|| "usage: rust-to-ti-c <input.rs> <output.c>".to_owned())?;
    let output = arguments.next().ok_or_else(usage)?;
    let output_format = match arguments.next() {
        None => OutputFormat::C,
        Some(argument) if argument == "--emit=ti-asm" => OutputFormat::TiAssembly,
        Some(_) => return Err(usage()),
    };

    if arguments.next().is_some() {
        return Err(usage());
    }

    let source = fs::read_to_string(&input)
        .map_err(|error| format!("cannot read {}: {error}", Path::new(&input).display()))?;
    let generated = match output_format {
        OutputFormat::C => translate_source(&source)?,
        OutputFormat::TiAssembly => translate_source_to_ti_asm(&source)?,
    };

    if let Some(parent) = Path::new(&output).parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("cannot create {}: {error}", parent.display()))?;
    }

    fs::write(&output, generated)
        .map_err(|error| format!("cannot write {}: {error}", Path::new(&output).display()))?;
    println!("Generated {}", Path::new(&output).display());
    Ok(())
}

#[derive(Clone, Copy)]
enum OutputFormat {
    C,
    TiAssembly,
}

fn usage() -> String {
    "usage: rust-to-ti-c <input.rs> <output> [--emit=ti-asm]".to_owned()
}

fn translate_source_to_ti_asm(source: &str) -> Result<String, String> {
    let file = syn::parse_file(source).map_err(|error| format!("invalid Rust syntax: {error}"))?;
    let functions = file
        .items
        .iter()
        .filter_map(|item| match item {
            Item::Fn(function) => Some(function),
            _ => None,
        })
        .collect::<Vec<_>>();

    if functions.is_empty() {
        return Err("no Rust function found".to_owned());
    }

    let mut output = String::from(
        "; Generated directly from parsed Rust syntax by rust-to-ti-c.\n\
         ; TI EABI: AL contains the first u16 argument; AH contains the second.\n\
         \t.sect \".text\"\n",
    );

    for (function_index, function) in functions.into_iter().enumerate() {
        let native = validate_native_binary_function(function)?;
        output.push_str(&format!(
            "\n\t.global {}\n\n{}:\n",
            native.name, native.name
        ));
        match native.operation {
            NativeOperation::Wrapping(mnemonic) => {
                output.push_str(&format!("\t{mnemonic} AL, AH\n"))
            }
            NativeOperation::WrappingImmediate { mnemonic, value } => {
                if value <= u8::MAX as u16 {
                    output.push_str(&format!("\tMOVB AH, #{value}\n"));
                } else {
                    output.push_str(&format!("\tMOV AH, #{value}\n"));
                }
                output.push_str(&format!("\t{mnemonic} AL, AH\n"));
            }
            NativeOperation::Multiply => output.push_str("\tMOV T, AH\n\tMPY ACC, T, AL\n"),
            NativeOperation::Xor => output.push_str("\tXOR AL, AH\n"),
            NativeOperation::Not => output.push_str("\tNOT AL\n"),
            NativeOperation::UnsignedMax => {
                let done = format!("rust_native_done_{function_index}");
                output.push_str(&format!(
                    "\tMOVZ AR6, AL\n\tMOV AL, AH\n\tCMP AL, AR6\n\tB {done}, HI\n\tMOV AL, AR6\n{done}:\n"
                ));
            }
            NativeOperation::UnsignedMin => {
                let done = format!("rust_native_done_{function_index}");
                output.push_str(&format!(
                    "\tMOVZ AR6, AL\n\tMOV AL, AH\n\tCMP AL, AR6\n\tB {done}, LOS\n\tMOV AL, AR6\n{done}:\n"
                ));
            }
            NativeOperation::UnpackLowByte => output.push_str("\tANDB AL, #255\n"),
            NativeOperation::UnpackHighByte => output.push_str("\tLSR AL, 8\n"),
            NativeOperation::WriteLowByte => output.push_str(
                "\tMOVZ AR6, AH\n\tMOV AH, AL\n\tAND AH, AH, #0xff00\n\tMOV AL, AR6\n\tANDB AL, #255\n\tOR AL, AH\n",
            ),
            NativeOperation::WriteHighByte => output.push_str("\tMOVB AL.MSB, AH\n"),
        }
        output.push_str("\tLRETR\n");
    }

    output.push_str(
        "\n\t.battr \"c28xabi\", Tag_File, 1, Tag_float_args(0)\n\
         \t.battr \"c28xabi\", Tag_File, 1, Tag_double_args(0)\n\
         \t.end\n",
    );
    Ok(output)
}

struct NativeBinaryFunction {
    name: String,
    operation: NativeOperation,
}

enum NativeOperation {
    Wrapping(&'static str),
    WrappingImmediate { mnemonic: &'static str, value: u16 },
    Multiply,
    Xor,
    Not,
    UnsignedMax,
    UnsignedMin,
    UnpackLowByte,
    UnpackHighByte,
    WriteLowByte,
    WriteHighByte,
}

fn validate_native_binary_function(function: &ItemFn) -> Result<NativeBinaryFunction, String> {
    if !matches!(function.vis, Visibility::Public(_)) {
        return Err("native function must be pub".to_owned());
    }
    let abi = function
        .sig
        .abi
        .as_ref()
        .and_then(|abi| abi.name.as_ref())
        .map(|name| name.value());
    if abi.as_deref() != Some("C") {
        return Err("native function must use extern \"C\"".to_owned());
    }
    if !has_no_mangle(&function.attrs)? {
        return Err("native function must have #[unsafe(no_mangle)]".to_owned());
    }
    if !(1..=2).contains(&function.sig.inputs.len()) {
        return Err("native function requires one or two u16 parameters".to_owned());
    }

    let mut parameters = Vec::new();
    for argument in &function.sig.inputs {
        let FnArg::Typed(argument) = argument else {
            return Err("native methods are not supported".to_owned());
        };
        require_u16(&argument.ty, "native parameter")?;
        let Pat::Ident(identifier) = argument.pat.as_ref() else {
            return Err("native parameter patterns are not supported".to_owned());
        };
        parameters.push(c_identifier(
            &identifier.ident.to_string(),
            "native parameter",
        )?);
    }

    let ReturnType::Type(_, return_type) = &function.sig.output else {
        return Err("native binary function must return u16".to_owned());
    };
    require_u16(return_type, "native return type")?;

    let operation = match function.block.stmts.as_slice() {
        [Stmt::Expr(body, None)] if classify_packed_byte_operation(body, &parameters).is_some() => {
            classify_packed_byte_operation(body, &parameters).unwrap()
        }
        [Stmt::Expr(Expr::Binary(binary), None)]
            if parameters.len() == 2 && matches!(binary.op, BinOp::BitXor(_)) =>
        {
            if expression_identifier(&binary.left)? != parameters[0]
                || expression_identifier(&binary.right)? != parameters[1]
            {
                return Err("native xor operands must preserve parameter order".to_owned());
            }
            NativeOperation::Xor
        }
        [Stmt::Expr(Expr::Unary(unary), None)]
            if parameters.len() == 1 && matches!(unary.op, syn::UnOp::Not(_)) =>
        {
            if expression_identifier(&unary.expr)? != parameters[0] {
                return Err("native not must use its only parameter".to_owned());
            }
            NativeOperation::Not
        }
        [Stmt::Expr(Expr::MethodCall(call), None)] if parameters.len() == 2 => {
            validate_native_wrapping(call, &parameters)?
        }
        [Stmt::Expr(Expr::If(expression), None)] if parameters.len() == 2 => {
            validate_native_unsigned_select(expression, &parameters)?
        }
        [Stmt::Local(local), Stmt::Expr(result, None)] if parameters.len() == 1 => {
            validate_native_immediate_local(local, result, &parameters[0])?
        }
        _ => return Err("native function body does not match a supported pattern".to_owned()),
    };

    Ok(NativeBinaryFunction {
        name: c_identifier(&function.sig.ident.to_string(), "native function")?,
        operation,
    })
}

fn strip_expression(expression: &Expr) -> &Expr {
    match expression {
        Expr::Paren(paren) => strip_expression(&paren.expr),
        Expr::Group(group) => strip_expression(&group.expr),
        other => other,
    }
}

fn literal_u16(expression: &Expr) -> Option<u16> {
    let Expr::Lit(literal) = strip_expression(expression) else {
        return None;
    };
    let Lit::Int(integer) = &literal.lit else {
        return None;
    };
    if !integer.suffix().is_empty() && integer.suffix() != "u16" {
        return None;
    }
    integer.base10_parse().ok()
}

fn identifier_is(expression: &Expr, expected: &str) -> bool {
    expression_identifier(strip_expression(expression)).is_ok_and(|name| name == expected)
}

fn masked_identifier(expression: &Expr, identifier: &str, mask: u16) -> bool {
    let Expr::Binary(binary) = strip_expression(expression) else {
        return false;
    };
    matches!(binary.op, BinOp::BitAnd(_))
        && identifier_is(&binary.left, identifier)
        && literal_u16(&binary.right) == Some(mask)
}

fn shifted_identifier(expression: &Expr, identifier: &str, amount: u16) -> bool {
    let Expr::Binary(binary) = strip_expression(expression) else {
        return false;
    };
    matches!(binary.op, BinOp::Shr(_))
        && identifier_is(&binary.left, identifier)
        && literal_u16(&binary.right) == Some(amount)
}

fn classify_packed_byte_operation(
    expression: &Expr,
    parameters: &[String],
) -> Option<NativeOperation> {
    if parameters.len() == 1 {
        if masked_identifier(expression, &parameters[0], 0x00ff) {
            return Some(NativeOperation::UnpackLowByte);
        }
        if shifted_identifier(expression, &parameters[0], 8) {
            return Some(NativeOperation::UnpackHighByte);
        }
        return None;
    }
    if parameters.len() != 2 {
        return None;
    }
    let Expr::Binary(or) = strip_expression(expression) else {
        return None;
    };
    if !matches!(or.op, BinOp::BitOr(_)) {
        return None;
    }
    if masked_identifier(&or.left, &parameters[0], 0xff00)
        && masked_identifier(&or.right, &parameters[1], 0x00ff)
    {
        return Some(NativeOperation::WriteLowByte);
    }
    let Expr::Binary(shift) = strip_expression(&or.right) else {
        return None;
    };
    if masked_identifier(&or.left, &parameters[0], 0x00ff)
        && matches!(shift.op, BinOp::Shl(_))
        && masked_identifier(&shift.left, &parameters[1], 0x00ff)
        && literal_u16(&shift.right) == Some(8)
    {
        return Some(NativeOperation::WriteHighByte);
    }
    None
}

fn validate_native_immediate_local(
    local: &syn::Local,
    result: &Expr,
    parameter: &str,
) -> Result<NativeOperation, String> {
    let Pat::Ident(local_identifier) = &local.pat else {
        return Err("native local must use a simple inferred identifier".to_owned());
    };
    let local_name = c_identifier(&local_identifier.ident.to_string(), "native local")?;
    if expression_identifier(result)? != local_name {
        return Err("native function must return its local variable".to_owned());
    }
    let Some(initializer) = &local.init else {
        return Err("native local requires an initializer".to_owned());
    };
    let Expr::MethodCall(call) = initializer.expr.as_ref() else {
        return Err("native local initializer must be a wrapping operation".to_owned());
    };
    if expression_identifier(&call.receiver)? != parameter || call.args.len() != 1 {
        return Err("native immediate operation must use its parameter as receiver".to_owned());
    }
    let Expr::Lit(literal) = &call.args[0] else {
        return Err("native immediate operand must be a u16 integer literal".to_owned());
    };
    let Lit::Int(integer) = &literal.lit else {
        return Err("native immediate operand must be a u16 integer literal".to_owned());
    };
    if !integer.suffix().is_empty() && integer.suffix() != "u16" {
        return Err("native immediate literal suffix must be u16".to_owned());
    }
    let value = integer
        .base10_parse::<u16>()
        .map_err(|_| "native immediate must fit in u16".to_owned())?;
    let mnemonic = if call.method == "wrapping_add" {
        "ADD"
    } else if call.method == "wrapping_sub" {
        "SUB"
    } else {
        return Err(format!("unsupported native operation {}", call.method));
    };
    Ok(NativeOperation::WrappingImmediate { mnemonic, value })
}

fn validate_native_wrapping(
    call: &syn::ExprMethodCall,
    parameters: &[String],
) -> Result<NativeOperation, String> {
    if call.args.len() != 1 {
        return Err("native wrapping operation requires one operand".to_owned());
    }
    let receiver = expression_identifier(&call.receiver)?;
    let operand = expression_identifier(&call.args[0])?;
    if receiver != parameters[0] || operand != parameters[1] {
        return Err("native operation operands must preserve parameter order".to_owned());
    }

    if call.method == "wrapping_mul" {
        return Ok(NativeOperation::Multiply);
    }
    let mnemonic = if call.method == "wrapping_add" {
        "ADD"
    } else if call.method == "wrapping_sub" {
        "SUB"
    } else {
        return Err(format!("unsupported native operation {}", call.method));
    };
    Ok(NativeOperation::Wrapping(mnemonic))
}

fn validate_native_unsigned_select(
    expression: &syn::ExprIf,
    parameters: &[String],
) -> Result<NativeOperation, String> {
    let Expr::Binary(condition) = expression.cond.as_ref() else {
        return Err("native if condition must be a comparison".to_owned());
    };
    if expression_identifier(&condition.left)? != parameters[0]
        || expression_identifier(&condition.right)? != parameters[1]
    {
        return Err("native selection comparison must preserve parameter order".to_owned());
    }
    let operation = match condition.op {
        BinOp::Ge(_) => NativeOperation::UnsignedMax,
        BinOp::Le(_) => NativeOperation::UnsignedMin,
        _ => return Err("native selection supports only >= or <= comparisons".to_owned()),
    };
    let [Stmt::Expr(then_value, None)] = expression.then_branch.stmts.as_slice() else {
        return Err("native max then branch must return the first parameter".to_owned());
    };
    if expression_identifier(then_value)? != parameters[0] {
        return Err("native max then branch must return the first parameter".to_owned());
    }
    let Some((_, else_expression)) = &expression.else_branch else {
        return Err("native max requires an else branch".to_owned());
    };
    let Expr::Block(else_block) = else_expression.as_ref() else {
        return Err("native max else branch must be a block".to_owned());
    };
    let [Stmt::Expr(else_value, None)] = else_block.block.stmts.as_slice() else {
        return Err("native max else branch must return the second parameter".to_owned());
    };
    if expression_identifier(else_value)? != parameters[1] {
        return Err("native max else branch must return the second parameter".to_owned());
    }
    Ok(operation)
}

fn translate_source(source: &str) -> Result<String, String> {
    let file = syn::parse_file(source).map_err(|error| format!("invalid Rust syntax: {error}"))?;
    let functions = file
        .items
        .iter()
        .filter_map(|item| match item {
            Item::Fn(function) => Some(function),
            _ => None,
        })
        .collect::<Vec<_>>();
    let foreign_functions = collect_foreign_functions(&file.items)?;

    if functions.len() != 1 {
        return Err(format!(
            "the prototype accepts exactly one Rust function, found {}",
            functions.len()
        ));
    }

    translate_function(functions[0], &foreign_functions)
}

fn translate_function(
    function: &ItemFn,
    foreign_functions: &BTreeMap<String, ForeignSignature>,
) -> Result<String, String> {
    if !matches!(function.vis, Visibility::Public(_)) {
        return Err("the exported function must be pub".to_owned());
    }

    let abi = function
        .sig
        .abi
        .as_ref()
        .and_then(|abi| abi.name.as_ref())
        .map(|name| name.value());
    if abi.as_deref() != Some("C") {
        return Err("the exported function must use extern \"C\"".to_owned());
    }

    if !has_no_mangle(&function.attrs)? {
        return Err("the exported function must have #[unsafe(no_mangle)]".to_owned());
    }

    let function_name = c_identifier(&function.sig.ident.to_string(), "function")?;

    if function.sig.inputs.is_empty() && matches!(function.sig.output, ReturnType::Default) {
        if foreign_functions.is_empty() {
            return translate_void_safe_hal_function(function, &function_name);
        }
        return translate_void_ffi_function(function, &function_name, foreign_functions);
    }

    let mut parameters = Vec::new();

    for argument in &function.sig.inputs {
        let FnArg::Typed(argument) = argument else {
            return Err("methods with self are not supported".to_owned());
        };
        require_u16(&argument.ty, "parameter")?;
        let Pat::Ident(identifier) = argument.pat.as_ref() else {
            return Err("parameter patterns are not supported".to_owned());
        };
        parameters.push(c_identifier(&identifier.ident.to_string(), "parameter")?);
    }

    if parameters.len() != 2 {
        return Err("wrapping_add prototype requires exactly two u16 parameters".to_owned());
    }

    let ReturnType::Type(_, return_type) = &function.sig.output else {
        return Err("the function must return u16".to_owned());
    };
    require_u16(return_type, "return type")?;

    let tail_expression = match function.block.stmts.as_slice() {
        [Stmt::Expr(expression, None)] => expression,
        _ => {
            return Err("the prototype function body must contain one tail expression".to_owned());
        }
    };

    let Expr::MethodCall(call) = tail_expression else {
        return Err("only u16::wrapping_add is currently supported".to_owned());
    };
    if call.method != "wrapping_add" || call.args.len() != 1 {
        return Err("only u16::wrapping_add is currently supported".to_owned());
    }

    let receiver = expression_identifier(&call.receiver)?;
    let operand = expression_identifier(&call.args[0])?;
    if receiver != parameters[0] || operand != parameters[1] {
        return Err("wrapping_add operands must be the two parameters in order".to_owned());
    }

    Ok(format!(
        "/* Generated from parsed Rust syntax by rust-to-ti-c.\n\
         * Supported subset: extern C fn(u16, u16) -> u16 with wrapping_add.\n\
         */\n\
         #include <limits.h>\n\n\
         #if USHRT_MAX != 65535U\n\
         #error \"Rust u16 requires a 16-bit unsigned short\"\n\
         #endif\n\n\
         typedef unsigned short rust_u16;\n\n\
         rust_u16 {function_name}(rust_u16 {}, rust_u16 {})\n\
         {{\n\
             return (rust_u16)({receiver} + {operand});\n\
         }}\n",
        parameters[0], parameters[1]
    ))
}

fn translate_void_safe_hal_function(
    function: &ItemFn,
    function_name: &str,
) -> Result<String, String> {
    let statements = function.block.stmts.as_slice();
    if matches!(statements.last(), Some(Stmt::Expr(Expr::Loop(_), _))) {
        return translate_adc_gpio_loop_function(statements, function_name);
    }
    if statements.len() > 3 {
        return translate_gpio_hal_function(statements, function_name);
    }
    if statements.len() != 3 {
        return Err("void Safe HAL function body must call system_init, take peripherals, then one HAL method".to_owned());
    }

    require_system_init_call(&statements[0])?;
    let peripheral_name = require_peripherals_take(&statements[1])?;
    let bridge_call = safe_hal_bridge_call(&statements[2], &peripheral_name)?;

    Ok(format!(
        "/* Generated from parsed Rust syntax by rust-to-ti-c.\n\
         * Supported subset: a no-argument C-ABI function containing one typed Safe HAL case call.\n\
         */\n\
         #include <limits.h>\n\n\
         #if USHRT_MAX != 65535U\n\
         #error \"Rust u16 requires a 16-bit unsigned short\"\n\
         #endif\n\n\
         typedef unsigned short rust_u16;\n\n\
         extern void f28035_system_init(void);\n\
         extern void {bridge_call}(void);\n\n\
         void {function_name}(void)\n\
         {{\n\
             f28035_system_init();\n\
             {bridge_call}();\n\
         }}\n"
    ))
}

/// Generic statement translator: supports multiple variables, if/else, loops.
fn translate_statement_generic(stmt: &Stmt, indent: &str) -> Result<String, String> {
    match stmt {
        Stmt::Local(local) => {
            // let x = expr;
            let pat = &local.pat;
            let var_name = match pat {
                syn::Pat::Ident(ident) => ident.ident.to_string(),
                _ => return Err("unsupported pattern".to_owned()),
            };
            let Some(init) = &local.init else { return Err("local needs initializer".to_owned()) };
            // If this is a method call like gpio.output::<39>(), record pin mapping
            if let Expr::MethodCall(call) = init.expr.as_ref() {
                if call.method == "output" || call.method == "input" {
                    if let Some(generics) = &call.turbofish {
                        if let Some(GenericArgument::Const(expr)) = generics.args.first() {
                            if let Some(pin) = literal_u16(expr) {
                                var_pin_map().lock().unwrap().insert(var_name.clone(), pin);
                            }
                        }
                    }
                }
                if call.method == "sample" {
                    if let Some(generics) = &call.turbofish {
                        if let Some(GenericArgument::Const(expr)) = generics.args.first() {
                            if let Some(ch) = literal_u16(expr) {
                                var_pin_map().lock().unwrap().insert(var_name.clone(), ch);
                            }
                        }
                    }
                }
            }
            let expr_c = translate_expr_generic(init.expr.as_ref())?;
            Ok(format!("{indent}rust_u16 {var_name} = {expr_c};\n"))
        }
        Stmt::Expr(expr, _) => {
            // Check if it's an if expression
            if let Expr::If(if_expr) = expr {
                // if condition { body } else { else_body }
                let cond = translate_expr_generic(&if_expr.cond)?;
                let then_block = &if_expr.then_branch;
                let mut then_c = String::new();
                for stmt in &then_block.stmts {
                    then_c.push_str(&translate_statement_generic(stmt, &format!("{indent}    "))?);
                }
                let mut else_c = String::new();
                if let Some((_, else_expr)) = &if_expr.else_branch {
                    else_c.push_str(&format!("{indent}}} else {{\n"));
                    if let Expr::Block(else_block) = else_expr.as_ref() {
                        for stmt in &else_block.block.stmts {
                            else_c.push_str(&translate_statement_generic(stmt, &format!("{indent}    "))?);
                        }
                    }
                }
                return Ok(format!("{indent}if ({cond}) {{\n{then_c}{else_c}{indent}}}\n"));
            }
            // function call or method call
            let c = translate_expr_generic(expr)?;
            Ok(format!("{indent}{c};\n"))
        }
        _ => Err("unsupported statement".to_owned()),
    }
}

fn translate_expr_generic(expr: &Expr) -> Result<String, String> {
    match expr {
        Expr::Call(call) => {
            // function call: f(a, b)
            let func_name = match call.func.as_ref() {
                Expr::Path(path) => path.path.segments.last().unwrap().ident.to_string(),
                _ => return Err("unsupported call target".to_owned()),
            };
            let args_c: Result<Vec<String>, String> = call.args.iter().map(translate_expr_generic).collect();
            let args = args_c?.join(", ");
            // Map common Safe HAL functions to C bridge names
            let c_func = match func_name.as_str() {
                "delay_us" => "f28035_delay_us",
                "delay_ms" => "f28035_delay_ms",
                "system_init" => "f28035_system_init",
                _ => func_name.as_str(),
            };
            Ok(format!("{c_func}({args})"))
        }
        Expr::MethodCall(call) => {
            // method call: map to C bridge function, look up pin from receiver variable
            let method = call.method.to_string();
            // Get receiver variable name (e.g. "led" from "led.set_low()")
            let receiver_name = match call.receiver.as_ref() {
                Expr::Path(path) => path.path.segments.last().unwrap().ident.to_string(),
                _ => "".to_string(),
            };
            match method.as_str() {
                "set_low" => {
                    let pin = var_pin_map().lock().unwrap().get(&receiver_name).copied()
                        .ok_or(format!("unknown pin for variable {receiver_name}"))?;
                    Ok(format!("f28035_gpio_write({pin}U, 0U)"))
                }
                "set_high" => {
                    let pin = var_pin_map().lock().unwrap().get(&receiver_name).copied()
                        .ok_or(format!("unknown pin for variable {receiver_name}"))?;
                    Ok(format!("f28035_gpio_write({pin}U, 1U)"))
                }
                "read" => {
                    let pin = var_pin_map().lock().unwrap().get(&receiver_name).copied()
                        .ok_or(format!("unknown pin for variable {receiver_name}"))?;
                    Ok(format!("f28035_gpio_read({pin}U)"))
                }
                "sample" => {
                    let ch = var_pin_map().lock().unwrap().get(&receiver_name).copied()
                        .ok_or(format!("unknown channel for variable {receiver_name}"))?;
                    Ok(format!("f28035_adc_sample({ch}U)"))
                }
                "delay_us" => {
                    let args_c: Result<Vec<String>, String> = call.args.iter().map(translate_expr_generic).collect();
                    let args = args_c?.join(", ");
                    Ok(format!("f28035_delay_us({args})"))
                }
                _ => {
                    // fallback: obj.method(a, b)
                    let receiver = translate_expr_generic(call.receiver.as_ref())?;
                    let args_c: Result<Vec<String>, String> = call.args.iter().map(translate_expr_generic).collect();
                    let args = args_c?.join(", ");
                    Ok(format!("{receiver}->{method}({args})"))
                }
            }
        }
        Expr::Binary(bin) => {
            // a + b
            let left = translate_expr_generic(bin.left.as_ref())?;
            let right = translate_expr_generic(bin.right.as_ref())?;
            let op = match bin.op {
                BinOp::Add(_) => "+",
                BinOp::Sub(_) => "-",
                BinOp::Mul(_) => "*",
                BinOp::Gt(_) => ">",
                BinOp::Lt(_) => "<",
                BinOp::Eq(_) => "==",
                BinOp::Ne(_) => "!=",
                BinOp::Or(_) => "||",
                BinOp::And(_) => "&&",
                BinOp::BitOr(_) => "|",
                BinOp::BitAnd(_) => "&",
                _ => return Err("unsupported binary op".to_owned()),
            };
            Ok(format!("({left} {op} {right})"))
        }
        Expr::Lit(lit) => {
            match &lit.lit {
                Lit::Int(int) => Ok(int.base10_digits().to_string()),
                Lit::Bool(b) => Ok(if b.value { "1" } else { "0" }.to_string()),
                _ => Err("unsupported literal".to_owned()),
            }
        }
        Expr::Path(path) => {
            let name = path.path.segments.last().unwrap().ident.to_string();
            Ok(name)
        }
        _ => Err("unsupported expression".to_owned()),
    }
}

/// Flexible ADC/GPIO loop translator: supports arbitrary statements in loop body.
fn translate_adc_gpio_loop_function(statements: &[Stmt], function_name: &str) -> Result<String, String> {
    // Find system_init (must be first)
    require_system_init_call(&statements[0])?;
    
    // Find Peripherals::take() (must be second)
    let peripherals = require_peripherals_take(&statements[1])?;
    
    // Collect setup statements: everything before the loop
    let loop_start = statements.iter().position(|s| {
        matches!(s, Stmt::Expr(Expr::Loop(_), _))
    }).ok_or("no loop found")?;
    
    let setup_statements = &statements[2..loop_start];
    
    // Collect setup C code
    let mut setup_c = String::new();
    let mut input_pin = 0u16;
    let mut output_pin = 0u16;
    let mut configured_channel = 0u16;
    let mut acqps = 0u16;
    
    for stmt in setup_statements {
        // Try input claim
        if let Ok((var_name, pin)) = require_hal_gpio_claim(stmt, &peripherals, "input") {
            input_pin = pin;
            var_pin_map().lock().unwrap().insert(var_name.clone(), pin);
            setup_c.push_str(&format!("    if (!f28035_gpio_make_input({pin}U, 1U, 0U)) {{ for (;;) {{}} }}\n"));
            continue;
        }
        // Try output claim
        if let Ok((var_name, pin)) = require_hal_gpio_claim(stmt, &peripherals, "output") {
            output_pin = pin;
            var_pin_map().lock().unwrap().insert(var_name.clone(), pin);
            setup_c.push_str(&format!("    if (!f28035_gpio_make_output({pin}U)) {{ for (;;) {{}} }}\n"));
            continue;
        }
        // Try ADC configure
        if let Ok((maybe_var_name, ch, acq)) = require_hal_adc_configure(stmt, &peripherals) {
            configured_channel = ch;
            acqps = acq;
            if let Some(var_name) = maybe_var_name {
                var_pin_map().lock().unwrap().insert(var_name, ch);
            }
            setup_c.push_str(&format!("    if (!f28035_adc_configure_soc0({ch}U, {acq}U)) {{ for (;;) {{}} }}\n"));
            continue;
        }
    }
    
    // Get loop body
    let Stmt::Expr(Expr::Loop(loop_expr), _) = &statements[loop_start] else {
        return Err("expected loop".to_owned());
    };
    let body = loop_expr.body.stmts.as_slice();
    
    // Translate loop body statements (generic)
    let mut loop_body_c = String::new();
    for stmt in body {
        loop_body_c.push_str(&translate_statement_generic(stmt, "        ")?);
    }
    
    Ok(format!(
        "/* Generated from validated Rust Safe HAL ADC/GPIO polling calls. */\n\
         #include <limits.h>\n\
         #if USHRT_MAX != 65535U\n\
         #error \"Rust u16 requires a 16-bit unsigned short\"\n\
         #endif\n\
         typedef unsigned short rust_u16;\n\
         extern void f28035_system_init(void);\n\
         extern rust_u16 f28035_take_peripherals(void);\n\
         extern rust_u16 f28035_gpio_make_input(rust_u16, rust_u16, rust_u16);\n\
         extern rust_u16 f28035_gpio_make_output(rust_u16);\n\
         extern rust_u16 f28035_gpio_read(rust_u16);\n\
         extern void f28035_gpio_write(rust_u16, rust_u16);\n\
         extern rust_u16 f28035_adc_configure_soc0(rust_u16, rust_u16);\n\
         extern rust_u16 f28035_adc_sample(rust_u16);\n\
         extern void f28035_delay_us(rust_u16);\n\
         void {function_name}(void)\n\
         {{\n\
             f28035_system_init();\n\
             if (!f28035_take_peripherals()) {{ for (;;) {{}} }}\n\
{setup_c}\
             for (;;) {{\n\
{loop_body_c}\
             }}\n\
         }}\n"
    ))
}

fn hal_const_args(call: &syn::ExprMethodCall, count: usize) -> Result<Vec<u16>, String> {
    let generics = call.turbofish.as_ref().ok_or("HAL method needs const arguments")?;
    if generics.args.len() != count {
        return Err(format!("HAL method needs {count} const arguments"));
    }
    generics.args.iter().map(|argument| {
        let GenericArgument::Const(expression) = argument else {
            return Err("HAL const argument must be a u16 literal".to_owned());
        };
        literal_u16(expression).ok_or("HAL const argument must be a u16 literal".to_owned())
    }).collect()
}

fn require_hal_field(expression: &Expr, peripheral_name: &str, field_name: &str) -> Result<(), String> {
    let Expr::Field(field) = expression else {
        return Err(format!("HAL receiver must be {peripheral_name}.{field_name}"));
    };
    if !matches!(&field.member, syn::Member::Named(name) if name == field_name)
        || !identifier_is(&field.base, peripheral_name)
    {
        return Err(format!("HAL receiver must be {peripheral_name}.{field_name}"));
    }
    Ok(())
}

fn require_hal_expect<'a>(expression: &'a Expr) -> Result<&'a syn::ExprMethodCall, String> {
    let Expr::MethodCall(expect) = expression else {
        return Err("HAL setup must end with .expect(\"message\")".to_owned());
    };
    if expect.method != "expect" || expect.args.len() != 1
        || !matches!(expect.args.first(), Some(Expr::Lit(syn::ExprLit { lit: Lit::Str(_), .. })))
    {
        return Err("HAL setup must end with .expect(\"message\")".to_owned());
    }
    let Expr::MethodCall(call) = expect.receiver.as_ref() else {
        return Err("HAL setup must call a Safe HAL method".to_owned());
    };
    Ok(call)
}

fn require_hal_gpio_claim(statement: &Stmt, peripherals: &str, direction: &str) -> Result<(String, u16), String> {
    let Stmt::Local(local) = statement else {
        return Err(format!("GPIO {direction} must be a local binding"));
    };
    let Pat::Ident(binding) = &local.pat else {
        return Err("GPIO binding must be a simple identifier".to_owned());
    };
    let initializer = local.init.as_ref().ok_or("GPIO binding needs an initializer")?;
    let call = require_hal_expect(&initializer.expr)?;
    if call.method != direction || !call.args.is_empty() {
        return Err(format!("GPIO binding must call gpio.{direction}::<PIN>()"));
    }
    require_hal_field(&call.receiver, peripherals, "gpio")?;
    let pin = hal_const_args(call, 1)?[0];
    if pin > 44 {
        return Err("GPIO pin must be 0..=44".to_owned());
    }
    Ok((c_identifier(&binding.ident.to_string(), "GPIO binding")?, pin))
}

fn require_hal_adc_configure(
    statement: &Stmt,
    peripherals: &str,
) -> Result<(Option<String>, u16, u16), String> {
    let (binding, expression) = match statement {
        Stmt::Local(local) => {
            let Pat::Ident(identifier) = &local.pat else {
                return Err("configured ADC handle needs a simple binding".to_owned());
            };
            let initializer = local.init.as_ref().ok_or("ADC setup needs an initializer")?;
            (Some(c_identifier(&identifier.ident.to_string(), "ADC handle")?), initializer.expr.as_ref())
        }
        Stmt::Expr(expression, Some(_)) => (None, expression),
        _ => return Err("ADC setup must be a statement or local binding".to_owned()),
    };
    let call = require_hal_expect(expression)?;
    let expected_method = if binding.is_some() { "into_soc0" } else { "configure_soc0" };
    if call.method != expected_method || !call.args.is_empty() {
        return Err(format!("ADC setup must call adc.{expected_method}::<CHANNEL, ACQPS>()"));
    }
    require_hal_field(&call.receiver, peripherals, "adc")?;
    let args = hal_const_args(call, 2)?;
    if args[0] > 15 || args[1] > 63 {
        return Err("ADC channel or acquisition window is out of range".to_owned());
    }
    Ok((binding, args[0], args[1]))
}

fn require_hal_adc_sample(
    statement: &Stmt,
    peripherals: &str,
    adc_handle: Option<&str>,
    configured_channel: u16,
) -> Result<(String, u16), String> {
    let Stmt::Local(local) = statement else {
        return Err("ADC sample must be a local binding".to_owned());
    };
    let Pat::Ident(binding) = &local.pat else {
        return Err("ADC sample binding must be a simple identifier".to_owned());
    };
    let initializer = local.init.as_ref().ok_or("ADC sample needs an initializer")?;
    let Expr::MethodCall(call) = initializer.expr.as_ref() else {
        return Err("ADC sample must call adc.sample::<CHANNEL>()".to_owned());
    };
    if call.method != "sample" || !call.args.is_empty() {
        return Err("ADC sample must call sample()".to_owned());
    }
    let channel = if let Some(handle) = adc_handle {
        if !identifier_is(&call.receiver, handle) || call.turbofish.is_some() {
            return Err(format!("ADC sample must call {handle}.sample()"));
        }
        configured_channel
    } else {
        require_hal_field(&call.receiver, peripherals, "adc")?;
        hal_const_args(call, 1)?[0]
    };
    if channel > 15 {
        return Err("ADC channel must be 0..=15".to_owned());
    }
    Ok((c_identifier(&binding.ident.to_string(), "ADC sample binding")?, channel))
}

fn require_hal_input_read(statement: &Stmt, input_name: &str) -> Result<String, String> {
    let Stmt::Local(local) = statement else {
        return Err("GPIO read must be a local binding".to_owned());
    };
    let Pat::Ident(binding) = &local.pat else {
        return Err("GPIO read binding must be a simple identifier".to_owned());
    };
    let initializer = local.init.as_ref().ok_or("GPIO read needs an initializer")?;
    let Expr::MethodCall(call) = initializer.expr.as_ref() else {
        return Err("GPIO read must call input.read()".to_owned());
    };
    if call.method != "read" || !call.args.is_empty() || call.turbofish.is_some()
        || !identifier_is(&call.receiver, input_name)
    {
        return Err("GPIO read must call input.read()".to_owned());
    }
    Ok(c_identifier(&binding.ident.to_string(), "GPIO read binding")?)
}

fn require_hal_condition(statement: &Stmt, button: &str, adc: &str, output: &str) -> Result<u16, String> {
    let Stmt::Expr(Expr::If(expression), _) = statement else {
        return Err("ADC/GPIO decision must be an if statement".to_owned());
    };
    if expression.else_branch.is_some() {
        return Err("ADC/GPIO decision does not support else".to_owned());
    }
    let Expr::Binary(or) = expression.cond.as_ref() else {
        return Err("ADC/GPIO decision needs button || adc > threshold".to_owned());
    };
    if !matches!(or.op, BinOp::Or(_)) || !identifier_is(&or.left, button) {
        return Err("ADC/GPIO decision needs button || adc > threshold".to_owned());
    }
    let Expr::Binary(compare) = or.right.as_ref() else {
        return Err("ADC/GPIO decision needs adc > threshold".to_owned());
    };
    if !matches!(compare.op, BinOp::Gt(_)) || !identifier_is(&compare.left, adc) {
        return Err("ADC/GPIO decision needs adc > threshold".to_owned());
    }
    let threshold = literal_u16(&compare.right).ok_or("ADC threshold must be a u16 literal")?;
    let [Stmt::Expr(Expr::MethodCall(action), Some(_))] = expression.then_branch.stmts.as_slice() else {
        return Err("ADC/GPIO decision must only set the output low".to_owned());
    };
    if action.method != "set_low" || !action.args.is_empty() || action.turbofish.is_some()
        || !identifier_is(&action.receiver, output)
    {
        return Err("ADC/GPIO decision must only set the output low".to_owned());
    }
    Ok(threshold)
}

fn require_hal_delay(statement: &Stmt) -> Result<u16, String> {
    let Stmt::Expr(Expr::Call(call), Some(_)) = statement else {
        return Err("ADC/GPIO loop must end with delay_us(microseconds);".to_owned());
    };
    if !identifier_is(&call.func, "delay_us") || call.args.len() != 1 {
        return Err("ADC/GPIO loop must end with delay_us(microseconds);".to_owned());
    }
    literal_u16(&call.args[0]).ok_or("delay must be a u16 literal".to_owned())
}

fn translate_gpio_hal_function(statements: &[Stmt], function_name: &str) -> Result<String, String> {
    require_system_init_call(&statements[0])?;
    let peripheral_name = require_peripherals_take(&statements[1])?;
    let mut pins = BTreeMap::<String, u16>::new();
    let mut calls = vec![
        "    f28035_system_init();".to_owned(),
        "    if (!f28035_take_peripherals()) { for (;;) {} }".to_owned(),
    ];
    let mut actions = 0;

    for statement in &statements[2..] {
        match statement {
            Stmt::Local(local) => {
                let Pat::Ident(binding) = &local.pat else {
                    return Err("GPIO binding must be a simple identifier".to_owned());
                };
                let Some(initializer) = &local.init else {
                    return Err("GPIO binding requires an initializer".to_owned());
                };
                let Expr::MethodCall(unwrap) = initializer.expr.as_ref() else {
                    return Err("GPIO binding must call output::<PIN>().expect(...)".to_owned());
                };
                if unwrap.method != "expect" || unwrap.args.len() != 1 {
                    return Err("GPIO binding must call output::<PIN>().expect(...)".to_owned());
                }
                let Expr::MethodCall(output) = unwrap.receiver.as_ref() else {
                    return Err("GPIO binding must call output::<PIN>().expect(...)".to_owned());
                };
                if output.method != "output" || !output.args.is_empty() {
                    return Err("GPIO binding must call output::<PIN>().expect(...)".to_owned());
                }
                let Expr::Field(gpio) = output.receiver.as_ref() else {
                    return Err("GPIO output receiver must be peripherals.gpio".to_owned());
                };
                let Expr::Path(base) = gpio.base.as_ref() else {
                    return Err("GPIO output receiver must be peripherals.gpio".to_owned());
                };
                if !matches!(&gpio.member, syn::Member::Named(name) if name == "gpio")
                    || base.path.segments.len() != 1
                    || base.path.segments[0].ident != peripheral_name
                {
                    return Err("GPIO output receiver must be peripherals.gpio".to_owned());
                }
                let Some(generics) = &output.turbofish else {
                    return Err("GPIO output requires a constant PIN".to_owned());
                };
                if generics.args.len() != 1 {
                    return Err("GPIO output requires one constant PIN".to_owned());
                }
                let Some(GenericArgument::Const(Expr::Lit(literal))) = generics.args.first() else {
                    return Err("GPIO output requires one constant PIN".to_owned());
                };
                let Lit::Int(integer) = &literal.lit else {
                    return Err("GPIO PIN must be an integer".to_owned());
                };
                let pin = integer.base10_parse::<u16>().map_err(|_| "GPIO PIN must be u16")?;
                if pin > 44 || pins.values().any(|existing| *existing == pin) {
                    return Err("GPIO PIN is invalid or already claimed".to_owned());
                }
                if pins.insert(binding.ident.to_string(), pin).is_some() {
                    return Err("GPIO binding is duplicated".to_owned());
                }
                calls.push(format!(
                    "    if (!f28035_gpio_make_output({pin}U)) {{ for (;;) {{}} }}"
                ));
            }
            Stmt::Expr(Expr::MethodCall(call), Some(_)) => {
                let Expr::Path(receiver) = call.receiver.as_ref() else {
                    return Err("GPIO action receiver must be a pin binding".to_owned());
                };
                if receiver.path.segments.len() != 1 || !call.args.is_empty() {
                    return Err("GPIO action requires a pin binding and no arguments".to_owned());
                }
                let name = receiver.path.segments[0].ident.to_string();
                let Some(pin) = pins.get(&name) else {
                    return Err(format!("unknown GPIO binding {name}"));
                };
                let statement = match call.method.to_string().as_str() {
                    "set_low" => format!("    f28035_gpio_write({pin}U, 0U);"),
                    "set_high" => format!("    f28035_gpio_write({pin}U, 1U);"),
                    "toggle" => format!("    f28035_gpio_toggle({pin}U);"),
                    _ => return Err(format!("unsupported GPIO action {}", call.method)),
                };
                calls.push(statement);
                actions += 1;
            }
            _ => return Err("unsupported GPIO HAL statement".to_owned()),
        }
    }
    if pins.is_empty() || actions == 0 {
        return Err("GPIO HAL entry needs an output pin and an action".to_owned());
    }

    Ok(format!(
        "/* Generated from supported Rust GPIO HAL calls. */\n\
         #include <limits.h>\n\
         #if USHRT_MAX != 65535U\n\
         #error \"Rust u16 requires a 16-bit unsigned short\"\n\
         #endif\n\
         typedef unsigned short rust_u16;\n\
         extern void f28035_system_init(void);\n\
         extern rust_u16 f28035_take_peripherals(void);\n\
         extern rust_u16 f28035_gpio_make_output(rust_u16);\n\
         extern void f28035_gpio_write(rust_u16, rust_u16);\n\
         extern void f28035_gpio_toggle(rust_u16);\n\
         void {function_name}(void)\n{{\n{}\n}}\n",
        calls.join("\n")
    ))
}

fn require_system_init_call(statement: &Stmt) -> Result<(), String> {
    let Stmt::Expr(Expr::Call(call), Some(_)) = statement else {
        return Err("first Safe HAL statement must be system_init();".to_owned());
    };
    let Expr::Path(path) = call.func.as_ref() else {
        return Err("first Safe HAL statement must be system_init();".to_owned());
    };
    if path.qself.is_some()
        || path.path.segments.len() != 1
        || path.path.segments[0].ident != "system_init"
        || !call.args.is_empty()
    {
        return Err("first Safe HAL statement must be system_init();".to_owned());
    }
    Ok(())
}

fn require_peripherals_take(statement: &Stmt) -> Result<String, String> {
    let Stmt::Local(local) = statement else {
        return Err("second Safe HAL statement must bind Peripherals::take().unwrap()".to_owned());
    };
    let Pat::Ident(identifier) = &local.pat else {
        return Err("peripherals binding must use a simple identifier".to_owned());
    };
    let Some(initializer) = &local.init else {
        return Err("peripherals binding requires an initializer".to_owned());
    };
    let Expr::MethodCall(unwrap_call) = initializer.expr.as_ref() else {
        return Err("peripherals binding must call Peripherals::take().unwrap()".to_owned());
    };
    if unwrap_call.method != "unwrap" || !unwrap_call.args.is_empty() {
        return Err("peripherals binding must call Peripherals::take().unwrap()".to_owned());
    }
    let Expr::Call(take_call) = unwrap_call.receiver.as_ref() else {
        return Err("peripherals binding must call Peripherals::take().unwrap()".to_owned());
    };
    let Expr::Path(path) = take_call.func.as_ref() else {
        return Err("peripherals binding must call Peripherals::take().unwrap()".to_owned());
    };
    if path.qself.is_some()
        || path.path.segments.len() != 2
        || path.path.segments[0].ident != "Peripherals"
        || path.path.segments[1].ident != "take"
        || !take_call.args.is_empty()
    {
        return Err("peripherals binding must call Peripherals::take().unwrap()".to_owned());
    }
    Ok(identifier.ident.to_string())
}

fn safe_hal_bridge_call(statement: &Stmt, peripheral_name: &str) -> Result<&'static str, String> {
    let call = match statement {
        Stmt::Expr(Expr::MethodCall(call), Some(_)) => call,
        Stmt::Local(local) => {
            let Some(initializer) = &local.init else {
                return Err("Safe HAL local requires an initializer".to_owned());
            };
            let Expr::MethodCall(call) = initializer.expr.as_ref() else {
                return Err("Safe HAL local initializer must be a HAL method call".to_owned());
            };
            call
        }
        _ => return Err("third Safe HAL statement must be a HAL method call".to_owned()),
    };

    let Expr::Field(field) = call.receiver.as_ref() else {
        return Err("Safe HAL method receiver must be peripherals.<resource>".to_owned());
    };
    let Expr::Path(base) = field.base.as_ref() else {
        return Err("Safe HAL method receiver must be peripherals.<resource>".to_owned());
    };
    if base.qself.is_some()
        || base.path.segments.len() != 1
        || base.path.segments[0].ident != peripheral_name
    {
        return Err("Safe HAL method receiver must use the Peripherals binding".to_owned());
    }
    let syn::Member::Named(resource_ident) = &field.member else {
        return Err("Safe HAL resource must be a named field".to_owned());
    };
    let resource = resource_ident.to_string();
    let method = call.method.to_string();

    if !call.args.is_empty() {
        return Err(format!("Safe HAL case {resource}.{method} does not lower runtime arguments"));
    }
    if resource == "i2c_a" && method != "reg_readback_sweep" {
        let address = hal_const_args(call, 1)?[0];
        if address != 0x36 {
            return Err(format!(
                "I2C case {method} uses fixed address 0x36; requested 0x{address:02X}"
            ));
        }
    } else if resource == "spi_b" && (method == "internal_loopback" || method == "triwire_loopback") {
        let bits = hal_const_args(call, 1)?[0];
        if bits != 8 {
            return Err(format!("SPI case {method} uses fixed 8-bit characters; requested {bits}"));
        }
    } else if resource == "sci_a"
        && (method == "configure_basic" || method == "internal_loopback" || method == "loopback_data_pattern")
    {
        return Err(format!(
            "SCI case {method} does not honor BAUD_DIV/CHAR_BITS; use a parameterized bridge before lowering it"
        ));
    } else if call.turbofish.is_some() {
        return Err(format!("Safe HAL case {resource}.{method} does not lower const arguments"));
    }

    match (resource.as_str(), method.as_str()) {
        ("spi_b", "reg_readback") => Ok("f28035_spi_reg_if_rw_basic"),
        ("spi_b", "internal_loopback") => Ok("f28035_spi_internal_loopback_basic"),
        ("spi_b", "triwire_loopback") => Ok("f28035_spi_triwire_loopback_basic"),
        ("spi_b", "loopback_mode_matrix") => Ok("f28035_spi_loopback_mode_matrix_basic"),
        ("spi_b", "charlen_sweep") => Ok("f28035_spi_charlen_sweep_basic"),
        ("spi_b", "fifo_rx_boundary") => Ok("f28035_spi_fifo_rx_boundary_basic"),
        ("spi_b", "fifo_tx_boundary") => Ok("f28035_spi_fifo_tx_boundary_basic"),
        ("spi_b", "fifo_level_boundary") => Ok("f28035_spi_fifo_level_boundary_basic"),
        ("spi_b", "multiple_frame_loopback") => Ok("f28035_spi_multiple_frame_loopback_basic"),
        ("spi_b", "nonfifo_interrupt_flag") => Ok("f28035_spi_nonfifo_intflag_irq_basic"),
        ("sci_a", "configure_basic") => Ok("f28035_sci_baud_program_basic"),
        ("sci_a", "baud_program_self_test") => Ok("f28035_sci_baud_program_basic"),
        ("sci_a", "reg_readback") => Ok("f28035_sci_reg_if_rw_basic"),
        ("sci_a", "internal_loopback") => Ok("f28035_sci_internal_loopback_basic"),
        ("sci_a", "internal_loopback_self_test") => Ok("f28035_sci_internal_loopback_basic"),
        ("sci_a", "loopback_data_pattern") => Ok("f28035_sci_loopback_data_pattern_basic"),
        ("sci_a", "loopback_data_pattern_self_test") => Ok("f28035_sci_loopback_data_pattern_basic"),
        ("sci_a", "fifo_reset_then_loopback") => Ok("f28035_sci_fifo_reset_then_loopback_basic"),
        ("sci_a", "fifo_rx") => Ok("f28035_sci_fifo_rx_basic"),
        ("sci_a", "rx_ready_clears_on_read") => Ok("f28035_sci_rxrdy_clear_on_read_basic"),
        ("sci_a", "charlen_sweep") => Ok("f28035_sci_sciccr_charlen_sweep_basic"),
        ("sci_a", "stop_parity_charlen_sweep") => Ok("f28035_sci_stop2_parity_charlen_sweep_basic"),
        ("sci_a", "tx_ready_interrupt_nonfifo") => Ok("f28035_sci_txrdy_int_nonfifo_basic"),
        ("i2c_a", "reg_readback_sweep") => Ok("f28035_i2c_reg_readback_sweep_basic"),
        ("i2c_a", "master_write_1byte") => Ok("f28035_i2c_master_write_1byte_basic"),
        ("i2c_a", "master_write_8byte_pattern") => Ok("f28035_i2c_master_write_8byte_pattern"),
        ("i2c_a", "master_read_1byte") => Ok("f28035_i2c_master_read_1byte_basic"),
        ("i2c_a", "master_read_8byte") => Ok("f28035_i2c_master_read_8byte_basic"),
        ("i2c_a", "master_write_back_to_back") => Ok("f28035_i2c_master_write_back_to_back"),
        ("i2c_a", "master_read_back_to_back") => Ok("f28035_i2c_master_read_back_to_back_basic"),
        ("i2c_a", "master_write_then_read_4byte") => {
            Ok("f28035_i2c_master_write_then_read_4byte_basic")
        }
        ("i2c_a", "repeated_start_write_then_read_4byte") => {
            Ok("f28035_i2c_master_repeated_start_write_then_read_4byte_basic")
        }
        ("i2c_a", "addr_nack_stop") => Ok("f28035_i2c_master_addr_nack_stop_basic"),
        ("lin_a", "baud_program") => Ok("f28035_lin_baud_program_basic"),
        ("lin_a", "header_break_sync_master") => Ok("f28035_lin_header_break_sync_master_basic"),
        ("lin_a", "iodft_loopback") => Ok("f28035_lin_iodft_loopback_basic"),
        ("lin_a", "reg_readback") => Ok("f28035_lin_reg_if_rw_basic"),
        ("lin_a", "rx_checksum_length") => Ok("f28035_lin_rx_checksum_length_real_basic"),
        ("lin_a", "rx_count_boundary") => Ok("f28035_lin_rx_rxcnt_num_boundary_real_basic"),
        ("lin_a", "sci_multibuf_read_slot_sweep") => {
            Ok("f28035_lin_sci_multibuf_rdslot_sweep_basic")
        }
        ("lin_a", "top_mode_loopback_power_cross") => {
            Ok("f28035_lin_top_mode_loopback_power_cross_basic")
        }
        ("lin_a", "tx_checksum_extended") => Ok("f28035_lin_tx_checksum_ext_real_basic"),
        ("lin_a", "wakeup_break_flag_route") => Ok("f28035_lin_wakeup_break_flag_route_basic"),
        ("ecap1", "reg_readback") => Ok("f28035_ecap_reg_rw_smoke"),
        ("ecap1", "apwm_matrix") => Ok("f28035_ecap_apwm_matrix"),
        ("ecap1", "capture_single_edge") => Ok("f28035_ecap_capture_single_edge"),
        ("ecap1", "capture_dual_edge") => Ok("f28035_ecap_capture_dual_edge"),
        ("ecap1", "capture_quad_edge") => Ok("f28035_ecap_capture_quad_edge"),
        ("ecap1", "capture_continuous_wrap") => Ok("f28035_ecap_capture_continuous_wrap"),
        ("ecap1", "capture_counter_reset") => Ok("f28035_ecap_capture_counter_reset"),
        ("ecap1", "capture_prescale_div2") => Ok("f28035_ecap_capture_prescale_div2"),
        ("ecap1", "capture_wrap_matrix") => Ok("f28035_ecap_capture_wrap_matrix"),
        ("ecap1", "interrupt_integration") => Ok("f28035_ecap_interrupt_integration"),
        ("eqep1", "register_write_readback") => Ok("f28035_eqep_register_wr"),
        ("eqep1", "polarity_test") => Ok("f28035_eqep_polarity_test"),
        ("eqep1", "count_basic") => Ok("f28035_eqep_count_basic"),
        ("eqep1", "mode_test") => Ok("f28035_eqep_mode_test"),
        ("eqep1", "compare_output_pulse") => Ok("f28035_eqep_compare_output_pulse"),
        ("eqep1", "unit_timer") => Ok("f28035_eqep_unit_timer"),
        ("eqep1", "unit_timeout") => Ok("f28035_eqep_unit_timeout_test"),
        ("eqep1", "watchdog_timeout") => Ok("f28035_eqep_watchdog_timeout_test"),
        ("eqep1", "interrupt_gate") => Ok("f28035_eqep_interrupt_gate"),
        ("eqep1", "reset_fsm_matrix") => Ok("f28035_eqep_reset_fsm_matrix"),
        _ => Err(format!("unsupported Safe HAL method {resource}.{method}")),
    }
}

fn collect_foreign_functions(items: &[Item]) -> Result<BTreeMap<String, ForeignSignature>, String> {
    let mut result = BTreeMap::new();

    for item in items {
        let Item::ForeignMod(foreign_module) = item else {
            continue;
        };
        let abi = foreign_module.abi.name.as_ref().map(|name| name.value());
        if abi.as_deref() != Some("C") {
            return Err("foreign functions must use extern \"C\"".to_owned());
        }

        for foreign_item in &foreign_module.items {
            let ForeignItem::Fn(function) = foreign_item else {
                return Err("only foreign functions are supported in extern blocks".to_owned());
            };
            let name = c_identifier(&function.sig.ident.to_string(), "foreign function")?;
            let mut parameter_count = 0;
            for argument in &function.sig.inputs {
                let FnArg::Typed(argument) = argument else {
                    return Err("foreign methods are not supported".to_owned());
                };
                require_u16(&argument.ty, "foreign parameter")?;
                parameter_count += 1;
            }
            let returns_u16 = match &function.sig.output {
                ReturnType::Default => false,
                ReturnType::Type(_, ty) => {
                    require_u16(ty, "foreign return type")?;
                    true
                }
            };
            if result
                .insert(
                    name,
                    ForeignSignature {
                        parameters: parameter_count,
                        returns_u16,
                    },
                )
                .is_some()
            {
                return Err("duplicate foreign function declaration".to_owned());
            }
        }
    }

    Ok(result)
}

fn translate_void_ffi_function(
    function: &ItemFn,
    function_name: &str,
    foreign_functions: &BTreeMap<String, ForeignSignature>,
) -> Result<String, String> {
    if foreign_functions.is_empty() {
        return Err("void prototype requires at least one declared foreign function".to_owned());
    }
    let [Stmt::Expr(Expr::Unsafe(unsafe_block), None)] = function.block.stmts.as_slice() else {
        return Err("void FFI function body must be one unsafe block".to_owned());
    };

    let mut calls = Vec::new();
    for statement in &unsafe_block.block.stmts {
        translate_ffi_statement(statement, foreign_functions, 1, &mut calls)?;
    }

    let mut declarations = Vec::new();
    for (name, signature) in foreign_functions {
        let result_type = if signature.returns_u16 {
            "rust_u16"
        } else {
            "void"
        };
        let parameters = if signature.parameters == 0 {
            "void".to_owned()
        } else {
            std::iter::repeat_n("rust_u16", signature.parameters)
                .collect::<Vec<_>>()
                .join(", ")
        };
        declarations.push(format!("extern {result_type} {name}({parameters});"));
    }

    Ok(format!(
        "/* Generated from parsed Rust syntax by rust-to-ti-c.\n\
         * Supported subset: a no-argument C-ABI function containing audited FFI calls.\n\
         */\n\
         #include <limits.h>\n\n\
         #if USHRT_MAX != 65535U\n\
         #error \"Rust u16 requires a 16-bit unsigned short\"\n\
         #endif\n\n\
         typedef unsigned short rust_u16;\n\n\
         {}\n\n\
         void {function_name}(void)\n\
         {{\n\
         {}\n\
         }}\n",
        declarations.join("\n"),
        calls.join("\n")
    ))
}

fn translate_ffi_statement(
    statement: &Stmt,
    foreign_functions: &BTreeMap<String, ForeignSignature>,
    indent: usize,
    output: &mut Vec<String>,
) -> Result<(), String> {
    let padding = "    ".repeat(indent);
    match statement {
        Stmt::Expr(Expr::Call(call), Some(_)) => {
            let (name, arguments, returns_u16) = ffi_call(call, foreign_functions)?;
            let prefix = if returns_u16 { "(void)" } else { "" };
            output.push(format!("{padding}{prefix}{name}({arguments});"));
        }
        Stmt::Local(local) => {
            let Pat::Ident(identifier) = &local.pat else {
                return Err("FFI local must use a simple identifier".to_owned());
            };
            let Some(initializer) = &local.init else {
                return Err("FFI local requires an initializer".to_owned());
            };
            let Expr::Call(call) = initializer.expr.as_ref() else {
                return Err("FFI local initializer must be a foreign call".to_owned());
            };
            let (callee, arguments, returns_u16) = ffi_call(call, foreign_functions)?;
            if !returns_u16 {
                return Err("FFI local initializer must return u16".to_owned());
            }
            let name = c_identifier(&identifier.ident.to_string(), "local")?;
            output.push(format!("{padding}rust_u16 {name} = {callee}({arguments});"));
        }
        Stmt::Expr(Expr::If(expression), None) => {
            if expression.else_branch.is_some() {
                return Err("FFI conditionals do not support else branches".to_owned());
            }
            let condition = translate_ffi_condition(&expression.cond, foreign_functions)?;
            output.push(format!("{padding}if ({condition}) {{"));
            for nested in &expression.then_branch.stmts {
                translate_ffi_statement(nested, foreign_functions, indent + 1, output)?;
            }
            output.push(format!("{padding}}}"));
        }
        Stmt::Expr(Expr::Return(expression), Some(_)) if expression.expr.is_none() => {
            output.push(format!("{padding}return;"));
        }
        _ => {
            return Err(
                "unsafe block supports FFI calls, u16 FFI locals, ==/!= conditionals, and return"
                    .to_owned(),
            );
        }
    }
    Ok(())
}

fn ffi_call(
    call: &syn::ExprCall,
    foreign_functions: &BTreeMap<String, ForeignSignature>,
) -> Result<(String, String, bool), String> {
    let Expr::Path(path) = call.func.as_ref() else {
        return Err("FFI call target must be a declared function name".to_owned());
    };
    if path.qself.is_some() || path.path.segments.len() != 1 {
        return Err("FFI call target must be a declared function name".to_owned());
    }
    let name = c_identifier(&path.path.segments[0].ident.to_string(), "FFI call")?;
    let signature = foreign_functions
        .get(&name)
        .ok_or_else(|| format!("call to undeclared foreign function {name}"))?;
    if call.args.len() != signature.parameters {
        return Err(format!(
            "foreign function {name} expects {} arguments, found {}",
            signature.parameters,
            call.args.len()
        ));
    }
    let arguments = call
        .args
        .iter()
        .map(u16_literal)
        .collect::<Result<Vec<_>, _>>()?
        .join(", ");
    Ok((name, arguments, signature.returns_u16))
}

fn translate_ffi_condition(
    expression: &Expr,
    foreign_functions: &BTreeMap<String, ForeignSignature>,
) -> Result<String, String> {
    let Expr::Binary(binary) = expression else {
        return Err("FFI condition must be a == or != comparison".to_owned());
    };
    let operator = match binary.op {
        BinOp::Eq(_) => "==",
        BinOp::Ne(_) => "!=",
        _ => return Err("FFI condition supports only == and !=".to_owned()),
    };
    let left = translate_ffi_condition_operand(&binary.left, foreign_functions)?;
    let right = translate_ffi_condition_operand(&binary.right, foreign_functions)?;
    Ok(format!("{left} {operator} {right}"))
}

fn translate_ffi_condition_operand(
    expression: &Expr,
    foreign_functions: &BTreeMap<String, ForeignSignature>,
) -> Result<String, String> {
    match expression {
        Expr::Call(call) => {
            let (name, arguments, returns_u16) = ffi_call(call, foreign_functions)?;
            if !returns_u16 {
                return Err("FFI call in a condition must return u16".to_owned());
            }
            Ok(format!("{name}({arguments})"))
        }
        Expr::Path(path) if path.qself.is_none() && path.path.segments.len() == 1 => c_identifier(
            &path.path.segments[0].ident.to_string(),
            "condition operand",
        ),
        Expr::Lit(_) => u16_literal(expression),
        _ => Err("FFI condition operand must be a call, local, or u16 literal".to_owned()),
    }
}

fn u16_literal(expression: &Expr) -> Result<String, String> {
    let Expr::Lit(literal) = expression else {
        return Err("FFI arguments must currently be u16 integer literals".to_owned());
    };
    let Lit::Int(integer) = &literal.lit else {
        return Err("FFI arguments must currently be u16 integer literals".to_owned());
    };
    let value = integer
        .base10_parse::<u16>()
        .map_err(|_| "FFI integer literal is outside the u16 range".to_owned())?;
    Ok(format!("{value}U"))
}

fn has_no_mangle(attributes: &[syn::Attribute]) -> Result<bool, String> {
    for attribute in attributes {
        if attribute.path().is_ident("no_mangle") {
            return Ok(true);
        }
        if attribute.path().is_ident("unsafe") {
            let mut found = false;
            attribute
                .parse_nested_meta(|meta| {
                    if meta.path.is_ident("no_mangle") {
                        found = true;
                        Ok(())
                    } else {
                        Err(meta.error("only no_mangle is supported in unsafe(...)"))
                    }
                })
                .map_err(|error| format!("invalid unsafe attribute: {error}"))?;
            if found {
                return Ok(true);
            }
        }
    }
    Ok(false)
}

fn require_u16(ty: &Type, position: &str) -> Result<(), String> {
    let Type::Path(path) = ty else {
        return Err(format!("{position} must be u16"));
    };
    if path.qself.is_some()
        || path.path.leading_colon.is_some()
        || path.path.segments.len() != 1
        || path.path.segments[0].ident != "u16"
    {
        return Err(format!("{position} must be u16"));
    }
    Ok(())
}

fn expression_identifier(expression: &Expr) -> Result<String, String> {
    let Expr::Path(path) = expression else {
        return Err("wrapping_add operands must be parameter names".to_owned());
    };
    if path.qself.is_some() || path.path.segments.len() != 1 {
        return Err("wrapping_add operands must be parameter names".to_owned());
    }
    c_identifier(&path.path.segments[0].ident.to_string(), "operand")
}

fn c_identifier(identifier: &str, position: &str) -> Result<String, String> {
    let mut characters = identifier.chars();
    let valid = characters
        .next()
        .is_some_and(|character| character == '_' || character.is_ascii_alphabetic())
        && characters.all(|character| character == '_' || character.is_ascii_alphanumeric());

    const C_KEYWORDS: &[&str] = &[
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else",
        "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register",
        "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef",
        "union", "unsigned", "void", "volatile", "while",
    ];

    if !valid || C_KEYWORDS.contains(&identifier) {
        return Err(format!(
            "{position} name {identifier:?} is not a portable C identifier"
        ));
    }
    Ok(identifier.to_owned())
}

#[cfg(test)]
mod tests {
    use super::translate_source;

    #[test]
    fn translates_names_and_wrapping_add_from_the_ast() {
        let generated = translate_source(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn sum16(left: u16, right: u16) -> u16 {
                left.wrapping_add(right)
            }
            "#,
        )
        .unwrap();

        assert!(generated.contains("rust_u16 sum16(rust_u16 left, rust_u16 right)"));
        assert!(generated.contains("return (rust_u16)(left + right);"));
    }

    #[test]
    fn rejects_normal_addition_because_overflow_semantics_are_not_explicit() {
        let error = translate_source(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn sum16(a: u16, b: u16) -> u16 { a + b }
            "#,
        )
        .unwrap_err();

        assert!(error.contains("wrapping_add"));
    }

    #[test]
    fn rejects_non_c_abi() {
        let error = translate_source(
            r#"
            #[unsafe(no_mangle)]
            pub fn sum16(a: u16, b: u16) -> u16 { a.wrapping_add(b) }
            "#,
        )
        .unwrap_err();

        assert!(error.contains("extern \"C\""));
    }

    #[test]
    fn translates_audited_void_ffi_calls() {
        let generated = translate_source(
            r#"
            unsafe extern "C" {
                fn configure(pin: u16) -> u16;
                fn write(pin: u16, high: u16);
            }

            #[unsafe(no_mangle)]
            pub extern "C" fn gpio_low() {
                unsafe {
                    configure(39);
                    write(39, 0);
                }
            }
            "#,
        )
        .unwrap();

        assert!(generated.contains("extern rust_u16 configure(rust_u16);"));
        assert!(generated.contains("(void)configure(39U);"));
        assert!(generated.contains("write(39U, 0U);"));
    }

    #[test]
    fn translates_ffi_readback_condition_and_early_return() {
        let generated = translate_source(
            r#"
            unsafe extern "C" {
                fn read(pin: u16) -> u16;
                fn fail(code: u16);
                fn pass();
            }

            #[unsafe(no_mangle)]
            pub extern "C" fn rust_main() {
                unsafe {
                    let observed = read(34);
                    if observed != 1 {
                        fail(0x0102);
                        return;
                    }
                    pass();
                }
            }
            "#,
        )
        .unwrap();

        assert!(generated.contains("rust_u16 observed = read(34U);"));
        assert!(generated.contains("if (observed != 1U)"));
        assert!(generated.contains("fail(258U);"));
        assert!(generated.contains("return;"));
        assert!(generated.contains("pass();"));
    }

    #[test]
    fn translates_typed_safe_hal_case_call() {
        let generated = translate_source(
            r#"
            use f28035_safe_hal::{system_init, Peripherals};

            #[unsafe(no_mangle)]
            pub extern "C" fn rust_main() {
                system_init();
                let mut peripherals = Peripherals::take().unwrap();
                let _loopback = peripherals.spi_b.internal_loopback::<8>();
            }
            "#,
        )
        .unwrap();

        assert!(generated.contains("extern void f28035_system_init(void);"));
        assert!(generated.contains("extern void f28035_spi_internal_loopback_basic(void);"));
        assert!(generated.contains("f28035_system_init();"));
        assert!(generated.contains("f28035_spi_internal_loopback_basic();"));
    }

    #[test]
    fn fixed_bridge_cases_reject_ignored_configuration() {
        for (call, message) in [
            ("peripherals.spi_b.internal_loopback::<9>()", "fixed 8-bit"),
            ("peripherals.i2c_a.master_write_1byte::<0x37>()", "fixed address 0x36"),
            ("peripherals.sci_a.configure_basic::<194, 8>()", "does not honor"),
        ] {
            let source = format!(
                "use f28035_safe_hal::{{Peripherals, system_init}};\n\
                 #[unsafe(no_mangle)] pub extern \"C\" fn rust_main() {{\n\
                 system_init(); let mut peripherals = Peripherals::take().unwrap();\n\
                 let _result = {call}; }}"
            );
            let error = translate_source(&source).unwrap_err();
            assert!(error.contains(message), "{call}: {error}");
        }
    }

    #[test]
    fn fixed_bridge_cases_keep_explicit_self_tests() {
        for (call, bridge) in [
            ("peripherals.sci_a.internal_loopback_self_test()", "f28035_sci_internal_loopback_basic();"),
            ("peripherals.i2c_a.master_write_1byte::<0x36>()", "f28035_i2c_master_write_1byte_basic();"),
        ] {
            let source = format!(
                "use f28035_safe_hal::{{Peripherals, system_init}};\n\
                 #[unsafe(no_mangle)] pub extern \"C\" fn rust_main() {{\n\
                 system_init(); let mut peripherals = Peripherals::take().unwrap();\n\
                 let _result = {call}; }}"
            );
            let generated = translate_source(&source).unwrap();
            assert!(generated.contains(bridge), "{call}");
        }
    }

    #[test]
    fn gpio_hal_actions_preserve_pin_and_call_order() {
        let generated = translate_source(
            r#"
            use f28035_safe_hal::{Peripherals, system_init};
            #[unsafe(no_mangle)]
            pub extern "C" fn rust_main() {
                system_init();
                let mut peripherals = Peripherals::take().unwrap();
                let mut gpio30 = peripherals.gpio.output::<30>().expect("GPIO30");
                gpio30.set_low();
                gpio30.toggle();
            }
            "#,
        )
        .unwrap();
        let configure = generated.find("f28035_gpio_make_output(30U)").unwrap();
        let low = generated.find("f28035_gpio_write(30U, 0U);").unwrap();
        let toggle = generated.find("f28035_gpio_toggle(30U);").unwrap();
        assert!(configure < low && low < toggle);
    }

    #[test]
    fn gpio_hal_rejects_duplicate_pin_claim() {
        let error = translate_source(
            r#"
            use f28035_safe_hal::{Peripherals, system_init};
            #[unsafe(no_mangle)]
            pub extern "C" fn rust_main() {
                system_init();
                let mut peripherals = Peripherals::take().unwrap();
                let mut first = peripherals.gpio.output::<30>().expect("GPIO30");
                let mut second = peripherals.gpio.output::<30>().expect("GPIO30");
                first.set_low();
            }
            "#,
        )
        .unwrap_err();
        assert!(error.contains("already claimed"));
    }

    #[test]
    fn safe_hal_adc_gpio_loop_preserves_parameters_and_order() {
        let generated = translate_source(
            r#"
            use f28035_safe_hal::{Peripherals, delay_us, system_init};
            #[unsafe(no_mangle)]
            pub extern "C" fn rust_main() {
                system_init();
                let mut peripherals = Peripherals::take().unwrap();
                let button = peripherals.gpio.input::<35>().expect("input");
                let mut output = peripherals.gpio.output::<40>().expect("output");
                let mut adc3 = peripherals.adc.into_soc0::<3, 9>().expect("ADC");
                loop {
                    let value = adc3.sample();
                    let pressed = button.read();
                    if pressed || value > 1024 {
                        output.set_low();
                    }
                    delay_us(1234);
                }
            }
            "#,
        ).unwrap();
        let configure = generated.find("f28035_adc_configure_soc0(3U, 9U)").unwrap();
        let sample = generated.find("rust_u16 value = f28035_adc_sample(3U)").unwrap();
        let read = generated.find("rust_u16 pressed = f28035_gpio_read(35U)").unwrap();
        let branch = generated.find("if (pressed != 0U || value > 1024U)").unwrap();
        let write = generated.find("f28035_gpio_write(40U, 0U)").unwrap();
        let delay = generated.find("f28035_delay_us(1234U)").unwrap();
        assert!(configure < sample && sample < read && read < branch && branch < write && write < delay);
    }

    #[test]
    fn safe_hal_adc_gpio_loop_rejects_different_sample_channel() {
        let error = translate_source(
            r#"
            use f28035_safe_hal::{Peripherals, delay_us, system_init};
            #[unsafe(no_mangle)]
            pub extern "C" fn rust_main() {
                system_init();
                let mut peripherals = Peripherals::take().unwrap();
                let button = peripherals.gpio.input::<34>().expect("input");
                let mut output = peripherals.gpio.output::<39>().expect("output");
                peripherals.adc.configure_soc0::<0, 7>().expect("ADC");
                loop {
                    let value = peripherals.adc.sample::<1>();
                    let pressed = button.read();
                    if pressed || value > 2048 {
                        output.set_low();
                    }
                    delay_us(50000);
                }
            }
            "#,
        ).unwrap_err();
        assert!(error.contains("differs from configured"));
    }

    #[test]
    fn emits_native_ti_assembly_without_a_c_intermediate() {
        let generated = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn rust_add(a: u16, b: u16) -> u16 {
                a.wrapping_add(b)
            }
            "#,
        )
        .unwrap();

        assert!(generated.contains(".global rust_add"));
        assert!(generated.contains("ADD AL, AH"));
        assert!(!generated.contains("#include"));
    }

    #[test]
    fn emits_multiple_native_functions_and_preserves_subtraction_order() {
        let generated = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn add16(a: u16, b: u16) -> u16 { a.wrapping_add(b) }

            #[unsafe(no_mangle)]
            pub extern "C" fn sub16(a: u16, b: u16) -> u16 { a.wrapping_sub(b) }
            "#,
        )
        .unwrap();

        assert!(generated.contains("add16:\n\tADD AL, AH"));
        assert!(generated.contains("sub16:\n\tSUB AL, AH"));
    }

    #[test]
    fn native_backend_rejects_reversed_operands() {
        let error = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn sub16(a: u16, b: u16) -> u16 { b.wrapping_sub(a) }
            "#,
        )
        .unwrap_err();

        assert!(error.contains("preserve parameter order"));
    }

    #[test]
    fn emits_native_unsigned_max_control_flow() {
        let generated = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn max16(a: u16, b: u16) -> u16 {
                if a >= b { a } else { b }
            }
            "#,
        )
        .unwrap();
        assert!(generated.contains("MOVZ AR6, AL"));
        assert!(generated.contains("CMP AL, AR6"));
        assert!(generated.contains("B rust_native_done_0, HI"));
    }

    #[test]
    fn native_max_rejects_wrong_branch_values() {
        let error = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn max16(a: u16, b: u16) -> u16 {
                if a >= b { b } else { a }
            }
            "#,
        )
        .unwrap_err();
        assert!(error.contains("then branch"));
    }

    #[test]
    fn emits_local_with_u16_immediate() {
        let generated = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn add_three(value: u16) -> u16 {
                let adjusted = value.wrapping_add(3u16);
                adjusted
            }
            "#,
        )
        .unwrap();
        assert!(generated.contains("MOVB AH, #3"));
        assert!(generated.contains("ADD AL, AH"));
    }

    #[test]
    fn emits_full_width_u16_immediate() {
        let generated = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn add_large(value: u16) -> u16 {
                let adjusted = value.wrapping_add(4660u16);
                adjusted
            }
            "#,
        )
        .unwrap();
        assert!(generated.contains("MOV AH, #4660"));
        assert!(!generated.contains("MOVB AH, #4660"));
    }

    #[test]
    fn emits_native_unsigned_min_control_flow() {
        let generated = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn min16(a: u16, b: u16) -> u16 {
                if a <= b { a } else { b }
            }
            "#,
        )
        .unwrap();
        assert!(generated.contains("B rust_native_done_0, LOS"));
    }

    #[test]
    fn emits_packed_byte_primitives() {
        let generated = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn low(word: u16) -> u16 { word & 0x00ffu16 }
            #[unsafe(no_mangle)]
            pub extern "C" fn high(word: u16) -> u16 { word >> 8u16 }
            #[unsafe(no_mangle)]
            pub extern "C" fn set_low(word: u16, value: u16) -> u16 {
                (word & 0xff00u16) | (value & 0x00ffu16)
            }
            #[unsafe(no_mangle)]
            pub extern "C" fn set_high(word: u16, value: u16) -> u16 {
                (word & 0x00ffu16) | ((value & 0x00ffu16) << 8u16)
            }
            "#,
        )
        .unwrap();
        assert!(generated.contains("low:\n\tANDB AL, #255"));
        assert!(generated.contains("high:\n\tLSR AL, 8"));
        assert!(generated.contains("AND AH, AH, #0xff00"));
        assert!(generated.contains("set_high:\n\tMOVB AL.MSB, AH"));
    }

    #[test]
    fn rejects_incorrect_packed_byte_mask() {
        let error = super::translate_source_to_ti_asm(
            r#"
            #[unsafe(no_mangle)]
            pub extern "C" fn low(word: u16) -> u16 { word & 0x01ffu16 }
            "#,
        )
        .unwrap_err();
        assert!(error.contains("does not match a supported pattern"));
    }
}
