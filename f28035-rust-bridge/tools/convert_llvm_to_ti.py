#!/usr/bin/env python3
"""把 LLVM 生成的 C28x 汇编转换成 TI 汇编器认识的格式，自动添加 stub 定义"""

import sys
import re


def split_comment(line):
    """把一行分成 (code, comment)，剥离行首空白。code 已 strip。"""
    s = line.strip()
    idx = s.find(';')
    if idx >= 0:
        return s[:idx].strip(), s[idx:]
    return s, ''


# C28x 寄存器（小写比较）
REGISTERS = {
    'ar0', 'ar1', 'ar2', 'ar3', 'ar4', 'ar5', 'ar6', 'ar7',
    'xar0', 'xar1', 'xar2', 'xar3', 'xar4', 'xar5', 'xar6', 'xar7',
    'acc', 'xt', 'sp', 'dp', 'pc', 'spl', 'aph', 'al', 'ah', 't', 'tr',
    'i0', 'i1', 'c', 'tc', 'pm', 'ovc',
}

# C28x 指令助记符（大写比较）
INSTRUCTIONS = {
    'MOV', 'MOVL', 'MOVZ', 'MOVB', 'ADD', 'ADDL', 'ADDB', 'SUB', 'SUBL', 'SUBB',
    'B', 'SB', 'SBF', 'SAR', 'SFB', 'IRET', 'NOP', 'POP', 'PUSH',
    'CLRC', 'SETC', 'EALLOW', 'EDIS', 'LSL', 'LSR', 'ASL', 'ASR',
    'AND', 'OR', 'XOR', 'CMP', 'CMPL', 'LCR', 'ROL', 'ROR', 'SBL',
    'UBRANCH', 'UCALL', 'LOOP', 'BANZ', 'PCB', 'KILL', 'ASTC',
}

# 分支条件码（大写比较）
CONDITIONS = {
    'UNC', 'EQ', 'NEQ', 'LT', 'LE', 'GT', 'GE',
    'HI', 'LO', 'CC', 'C', 'NC', 'NC', 'TC', 'NGC', 'GEQ', 'LSPM',
}


def scan_symbols(lines):
    """第一遍扫描：返回 (defined, referenced) 集合。"""
    defined = set()
    referenced = set()

    for line in lines:
        code, comment = split_comment(line)
        if not code:
            continue

        # 标签：code 以 : 结尾
        if code.endswith(':'):
            sym = code[:-1].strip()
            if sym:
                defined.add(sym)

        # .global / .def / .ref 等导出声明
        m = re.match(r'^\.(?:global|def|ref|globl)\s+(\S+)', code)
        if m:
            defined.add(m.group(1))

        # 伪指令行（. 开头）不做引用扫描
        if code.startswith('.'):
            continue

        # 指令行：提取操作数中的符号引用
        # 去掉逗号、#、@、*、括号
        ops = re.sub(r'[,#@*()]', ' ', code).split()
        # 第一个 token 是指令助记符
        for tok in ops:
            if tok.startswith('$'):
                continue
            low = tok.lower()
            up = tok.upper()
            if low in REGISTERS:
                continue
            if up in INSTRUCTIONS:
                continue
            if up in CONDITIONS:
                continue
            # 纯数字（十进制、0x 十六进制、0b 二进制）
            if re.match(r'^-?0[xXbB][0-9a-fA-F]+$', tok):
                continue
            if re.match(r'^-?[0-9]+$', tok):
                continue
            # 看起来像符号
            if re.match(r'^[A-Za-z_.][A-Za-z0-9_]*$', tok) and len(tok) > 2:
                if tok.startswith('.'):
                    # .Lxxx 这类局部符号在文件里有定义（数据段），跳过
                    continue
                referenced.add(tok)

    return defined, referenced


def convert_data_line(code, comment):
    """转换数据段伪指令行为 TI 语法。返回输出行（不含换行），或 None 表示跳过。"""
    # .asciz "..." -> .string "..."
    m = re.match(r'^\.asciz\s+(.+)$', code)
    if m:
        return f'    .string {m.group(1)}'

    # .ascii "..." -> .string (TI 没有 .ascii，用 .string 但不加 null? 这里按 string 处理)
    m = re.match(r'^\.ascii\s+(.+)$', code)
    if m:
        return f'    .string {m.group(1)}'

    # .long sym -> .long SYM (大写符号引用)
    m = re.match(r'^\.long\s+(.+)$', code)
    if m:
        operands = m.group(1).strip()
        # 逗号分隔多个操作数，逐个大写符号
        parts = [p.strip() for p in operands.split(',')]
        out_parts = []
        for p in parts:
            if re.match(r'^[A-Za-z_.][A-Za-z0-9_]*$', p):
                out_parts.append(p.upper())
            else:
                out_parts.append(p)
        return f'    .long {", ".join(out_parts)}'

    # .word/.short/.uword 类似处理
    m = re.match(r'^\.(?:word|short|uword|bss|usect)\b', code)
    if m:
        return None  # 跳过对齐/bss 类指令

    # .p2align / .align / .balign 跳过
    if re.match(r'^\.p?2?align\b', code) or re.match(r'^\.balign\b', code):
        return None

    # .cfi_* 调试指令跳过
    if code.startswith('.cfi_'):
        return None

    # 其他 . 开头的伪指令：保留但大写
    return f'    {code.upper()}'


def convert(input_file, output_file):
    with open(input_file, 'r') as f:
        lines = f.readlines()

    # 第一遍：扫描符号
    defined, referenced = scan_symbols(lines)
    undefined = referenced - defined

    # 分类未定义符号：函数 stub vs 数据 stub
    func_stubs = sorted(undefined)
    # （.Lalloc_* 在扫描时已被跳过，不会出现在 referenced 里）

    # 生成 stub
    stubs = []
    stubs.append('; === Auto-generated stubs for undefined symbols ===\n')
    if func_stubs:
        stubs.append('    .sect ".text"\n')
        for sym in func_stubs:
            up = sym.upper()
            stubs.append(f'    .global {up}\n')
            stubs.append(f'{up}:\n')
            stubs.append(f'    LRETR\n')
            stubs.append('\n')
    stubs.append('; === End of stubs ===\n\n')

    # 第二遍：转换主文件
    result = list(stubs)

    # 先放代码段
    result.append('    .sect ".text"\n\n')

    in_data_section = False  # 遇到 .Lalloc_* 标签后切到 .econst
    pending_directive = None  # 记录段切换

    for line in lines:
        code, comment = split_comment(line)

        if not code:
            result.append('\n')
            continue

        # 标签行（code 以 : 结尾）
        if code.endswith(':'):
            sym = code[:-1].strip()
            # 数据段标签（.L 开头）：切到 .econst，并大写以匹配指令行里的大写引用
            if sym.startswith('.L'):
                if not in_data_section:
                    result.append('    .sect ".econst"\n\n')
                    in_data_section = True
                new_line = sym.upper() + ':'
            else:
                # 外部函数标签保持原大小写（启动代码用原名字调用）
                new_line = sym + ':'
            if comment:
                new_line += f' {comment}'
            result.append(new_line + '\n')
            continue

        # 伪指令行
        if code.startswith('.'):
            # .global 保留（符号名保持原大小写，外部代码按原名引用）
            m = re.match(r'^\.global\s+(\S+)', code)
            if m:
                sym = m.group(1)
                new_line = f'    .global {sym}'
                if comment:
                    new_line += f' {comment}'
                result.append(new_line + '\n')
                continue

            # 数据段伪指令
            if in_data_section:
                out = convert_data_line(code, comment)
                if out is not None:
                    if comment:
                        out += f' {comment}'
                    result.append(out + '\n')
                continue

            # 代码段里的伪指令：跳过 .p2align/.cfi_*
            if re.match(r'^\.p?2?align\b', code) or code.startswith('.cfi_') or code.startswith('.balign'):
                continue
            # 其他伪指令注释掉
            new_line = f'; {code} (ignored)'
            if comment:
                new_line += f' {comment}'
            result.append(new_line + '\n')
            continue

        # 指令行：全部转大写
        new_line = '    ' + code.upper()
        if comment:
            new_line += f' {comment}'
        result.append(new_line + '\n')

    with open(output_file, 'w') as f:
        f.writelines(result)

    print(f'Done: {input_file} -> {output_file}')
    print(f'Total lines: {len(result)}')
    print(f'Defined symbols: {len(defined)}')
    print(f'Referenced symbols: {len(referenced)}')
    print(f'Undefined (stubbed): {len(func_stubs)}')
    for s in func_stubs:
        print(f'  stub: {s}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('Usage: convert_llvm_to_ti.py input.s output.s')
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
