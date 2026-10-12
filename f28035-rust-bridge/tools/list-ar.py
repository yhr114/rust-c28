import sys
with open(sys.argv[1], 'rb') as f:
    print('magic', f.read(8))
    while True:
        hdr = f.read(60)
        if len(hdr) < 60:
            break
        name = hdr[0:16]
        size = int(hdr[48:58].decode().strip())
        print('name=', name, 'size=', size, 'fmag=', hdr[58:60])
        data = f.read(size)
        if name.startswith(b'#1/'):
            nlen = int(name[3:])
            print('  bsd-name:', data[:nlen])
        if size % 2:
            f.read(1)
