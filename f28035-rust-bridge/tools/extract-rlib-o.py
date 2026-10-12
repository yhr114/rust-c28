#!/usr/bin/env python3
"""Extract *.o members from a Rust rlib (GNU ar archive) to a directory."""
import os
import sys

def extract(ar_path, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    extracted = []
    with open(ar_path, 'rb') as f:
        magic = f.read(8)
        if magic != b'!<arch>\n':
            raise SystemExit(f'not an ar archive: {ar_path}')
        longnames = b''
        members = []
        while True:
            hdr = f.read(60)
            if len(hdr) < 60:
                break
            raw_name = hdr[0:16].decode('ascii', 'replace')
            size = int(hdr[48:58].decode().strip())
            data = f.read(size)
            if size % 2:
                f.read(1)
            members.append((raw_name, data))
        for raw_name, data in members:
            name = raw_name.strip()
            if name == '//':
                longnames = data
                continue
            if name == '/':
                continue  # symbol table
            if name.startswith('/'):
                # longname reference: /<offset> into longnames
                off = int(name[1:])
                end = longnames.find(b'/\n', off)
                real = longnames[off:end].decode('ascii', 'replace')
            elif name.endswith('/'):
                real = name[:-1]
            else:
                real = name
            if real.endswith('.o'):
                out_path = os.path.join(out_dir, real)
                with open(out_path, 'wb') as o:
                    o.write(data)
                extracted.append(out_path)
    return extracted

if __name__ == '__main__':
    ar_path, out_dir = sys.argv[1], sys.argv[2]
    for p in extract(ar_path, out_dir):
        print(p, os.path.getsize(p))
