"""Prepare Vivado SDF bus checks and verify VCS timing annotation."""

import argparse
from collections import Counter
from itertools import product
from pathlib import Path
import re


def expand(source, destination):
    # Vivado writes one timing check per bus; VCS -tcheckvecsplit needs each bit.
    # Only port references change: all edge qualifiers and delay tuples survive.
    bus = re.compile(r'\b([A-Za-z_][A-Za-z_0-9]*)\[(\d+):(\d+)\]')
    check = re.compile(r'\s*\((SETUPHOLD|SETUP|HOLD|RECREM|RECOVERY|REMOVAL|WIDTH|PERIOD)\b')
    if source.resolve() == destination.resolve():
        raise ValueError('Keep the original SDF separate from the expanded SDF')
    changed = expanded = 0
    with source.open() as src, destination.open('w') as dst:
        for line in src:
            buses = list(bus.finditer(line)) if check.match(line) else []
            if not buses:
                dst.write(line)
                continue
            changed += 1
            ranges = [range(min(int(m[2]), int(m[3])), max(int(m[2]), int(m[3])) + 1)
                      for m in buses]
            for indices in product(*ranges):
                scalar = line
                for match, index in reversed(list(zip(buses, indices))):
                    scalar = scalar[:match.start()] + '%s[%d]' % (match[1], index) + scalar[match.end():]
                dst.write(scalar)
                expanded += 1
    print('Expanded %d bus timing checks into %d bit checks.' % (changed, expanded))


def verify(directory):
    annotation = (directory / 'sdfAnnotateInfo').read_text()
    compilation = (directory / 'compile.log').read_text(errors='replace')

    def count(label, default=None):
        match = re.search(r'^#\s*' + re.escape(label) + r'\s*=\s*(\d+)', annotation, re.MULTILINE)
        if match:
            return int(match[1])
        if default is not None:
            return default
        raise ValueError('Missing SDF annotation count: ' + label)

    checks = {name: count(name, 0) for name in
              ('SETUPHOLD', 'SETUP', 'HOLD', 'RECREM', 'RECOVERY', 'REMOVAL', 'WIDTH', 'PERIOD')}
    expected = sum(checks.values()) + checks['SETUPHOLD'] + checks['RECREM']
    if (not expected or sum(checks.values()) != count('TIMINGCHECK(ALL)') or
            expected != count('Timing Checks') or
            not count('IOPATH') or count('IOPATH') != count('IOPATH Delays') or
            not count('INTERCONNECT') or count('INTERCONNECT') != count('INTERCONNECT(MSID)')):
        raise ValueError('Incomplete SDF annotation; see sdfAnnotateInfo')

    warnings = Counter(re.findall(r'Warning-\[([^]]+)\]', compilation))
    # These two warnings explicitly state that the wire delays are still applied.
    rejected = sorted(w for w in warnings if w.startswith('SDF') and
                      w not in ('SDFCOM_SWC', 'SDFCOM_IWSBA'))
    if rejected or re.search(r'^Error-', compilation, re.MULTILINE):
        raise ValueError('SDF compilation errors/warnings: ' + ', '.join(rejected))
    print('SDF annotation: %d cell paths, %d interconnects, %d timing checks.' %
          (count('IOPATH'), count('INTERCONNECT'), expected))
    if warnings['NTCDNC']:
        # Original vendor models retain both clock polarities on shared delayed
        # nets. VCS can round negative limits to zero when these checks conflict.
        print('WARNING: VCS adjusted negative timing limits (%d NTCDNC warnings); '
              'the original negative constraints are not all preserved.' % warnings['NTCDNC'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command')
    commands.required = True
    conversion = commands.add_parser('expand')
    conversion.add_argument('source', type=Path)
    conversion.add_argument('destination', type=Path)
    verification = commands.add_parser('check')
    verification.add_argument('directory', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'expand':
            expand(args.source, args.destination)
        else:
            verify(args.directory)
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
