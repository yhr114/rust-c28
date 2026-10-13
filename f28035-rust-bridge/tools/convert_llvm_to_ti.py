#!/usr/bin/env python3
"""把 LLVM 生成的 C28x 汇编转换成 TI 汇编器认识的格式，自动添加 stub 定义"""

import sys
import re

def convert(input_file, output_file):
    with open(input_file, 'r') as f:
        lines = f.readlines()
    
    # 第一步：先扫描所有行，收集所有引用的符号
    referenced_symbols = set()
    defined_symbols = set()
    
    for line in lines:
        trimmed = line.strip()
        if not trimmed:
            continue
        
        # 标签行（定义符号）
        if trimmed.endswith(':') and not trimmed.startswith('.'):
            sym = trimmed[:-1]
            defined_symbols.add(sym)
        
        # .global 行（定义符号）
        m = re.match(r'^\.global\s+(.+)$', trimmed)
        if m:
            sym = m.group(1).strip()
            defined_symbols.add(sym)
        
        # 指令行中的符号引用（简单粗暴：所有看起来像符号的单词）
        # 跳过指令和寄存器
        parts = trimmed.replace(',', ' ').replace('#', ' ').replace('@', ' ').split()
        # C28x 寄存器列表
        registers = ['ar0', 'ar1', 'ar2', 'ar3', 'ar4', 'ar5', 'ar6', 'ar7',
                     'xar0', 'xar1', 'xar2', 'xar3', 'xar4', 'xar5', 'xar6', 'xar7',
                     'acc', 'xt', 'sp', 'dp', 'pc', 'spl', 'aph', 'al', 'ah', 't', 'tr',
                     'i0', 'i1']
        for part in parts:
            # 跳过数字、寄存器、指令
            if part.startswith('$') or part.startswith('*'):
                continue
            if part.lower() in [r.lower() for r in registers]:
                continue
            if part.upper() in ['MOV', 'MOVL', 'ADD', 'SUB', 'B', 'SB', 'IRET', 'NOP',
                               'PUSH', 'POP', 'CLRC', 'SETC', 'EALLOW', 'EDIS',
                               'LSL', 'LSR', 'ASL', 'ASR', 'AND', 'OR', 'XOR',
                               'CMP', 'CMPL', 'MOVZ', 'ADDB', 'SUBB', 'SBL', 'LCR',
                               'ADDL', 'SUBL', 'ROL', 'ROR']:
                continue
            if re.match(r'^[0-9xXa-fA-F]+$', part):
                continue
            # 看起来像符号的（字母开头，包含下划线或大写）
            if re.match(r'^[A-Za-z_.][A-Za-z0-9_]*$', part) and len(part) > 2:
                # 跳过伪指令
                if part.startswith('.'):
                    continue
                referenced_symbols.add(part)
    
    # 第二步：找出未定义的符号
    undefined = referenced_symbols - defined_symbols
    
    # 第三步：生成 stub 定义
    stubs = []
    stubs.append('; === Auto-generated stubs for undefined symbols ===\n')
    
    # 函数 stub（看起来像函数名的，比如 panic、enable_int）
    func_stubs = []
    data_stubs = []
    
    for sym in sorted(undefined):
        # .LALLOC_* 是数据符号
        if sym.startswith('.LALLOC_'):
            data_stubs.append(sym)
        else:
            # 其他都当成函数 stub
            func_stubs.append(sym)
    
    # 函数 stub 放在 .text 段
    if func_stubs:
        stubs.append('    .sect ".text"\n')
        for sym in func_stubs:
            stubs.append(f'    .global {sym}\n')
            stubs.append(f'{sym}:\n')
            stubs.append(f'    SB $, UNC\n')  # 无限循环
            stubs.append('\n')
    
    # 数据 stub 放在 .ebss 段
    if data_stubs:
        stubs.append('    .sect ".ebss"\n')
        for sym in data_stubs:
            stubs.append(f'{sym}:\n')
            stubs.append(f'    .usect ".ebss", 16\n')  # 每个分配 16 字节
            stubs.append('\n')
    
    stubs.append('; === End of stubs ===\n')
    stubs.append('\n')
    
    # 第四步：转换主文件
    result = []
    # 先加 stub
    result.extend(stubs)
    # 再加段定义
    result.append('    .sect ".text"\n')
    result.append('\n')
    
    for line in lines:
        trimmed = line.strip()
        
        # 空行
        if not trimmed:
            result.append('\n')
            continue
        
        # 分离注释
        code = trimmed
        comment = ''
        idx = trimmed.find(';')
        if idx >= 0:
            code = trimmed[:idx].strip()
            comment = trimmed[idx:]
        
        # 伪指令行（. 开头）
        if code.startswith('.'):
            # 保留 .global，其他伪指令加注释
            m = re.match(r'^\.global\s+(.+)$', code)
            if m:
                sym = m.group(1)
                new_line = f'    .global {sym}'
            else:
                new_line = f'; {code} (ignored)'
            if comment:
                new_line += f' {comment}'
            result.append(new_line + '\n')
            continue
        
        # 标签行（: 结尾）
        if code.endswith(':'):
            new_line = code.upper()
            if comment:
                new_line += f' {comment}'
            result.append(new_line + '\n')
            continue
        
        # 指令行 - 全部转大写
        if len(code) > 0:
            new_line = '    ' + code.upper()
            if comment:
                new_line += f' {comment}'
            result.append(new_line + '\n')
            continue
        
        # 其他
        result.append(trimmed + '\n')
    
    with open(output_file, 'w') as f:
        f.writelines(result)
    
    print(f'Done: {input_file} -> {output_file}')
    print(f'Total lines: {len(result)}')
    print(f'Undefined symbols: {len(undefined)}')
    print(f'  Function stubs: {len(func_stubs)}')
    print(f'  Data stubs: {len(data_stubs)}')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('Usage: convert_llvm_to_ti.py input.s output.s')
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
