import sys
for f in sys.argv[1:]:
    text = open(f, encoding='utf-8').read()
    lines = text.split('\n')
    open_count = 0
    close_count = 0
    for i, line in enumerate(lines, 1):
        o = line.count('(')
        c = line.count(')')
        open_count += o
        close_count += c
        if o != c and i > 80 and i < 200:
            print(f'{f}:{i} +{o} -{c} | {line.strip()[:80]}')
    print(f'{f}: total open={open_count}, close={close_count}, diff={open_count-close_count}')
