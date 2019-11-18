from sys import argv
from os import path as osp
import csv

color_dict = {'LIVE': "\033[92;1m",
              'EXC' : "\033[91;1m",
              'FAIL': "\033[93;1m",
              'TIME': "\033[94;1m",
              'NA': "\033[95;1m"
             }

def color(status):
    return color_dict[status.strip()] + status + "\033[0m"

dirs = argv[1:]
if not dirs:
    print("\nusage: python3 compare.py dir1 dir2 ...")
    print("       Each dir should contain the results of a run of defects4j mutation")
    print("       In particular, kill.csv should be present")
    from sys import exit
    exit(1)

statuses = []

lines = []
for d in dirs:
    with open(osp.join(d, 'kill.csv')) as f:
        lines.append(f.readlines()[1:])
zipped = list(zip(*lines))

for entry in zipped:
    statuses.append(tuple((x.split(',')[1].strip() for x in entry)))

bad = 0
very_bad = 0

print("File summary")
for i, d in enumerate(dirs):
    print(i+1, osp.join(d, 'kill.csv'))

print(" #  mut-id  {}".format("   ".join(["{:^3}".format(x) for x in range(1, len(dirs) + 1) ])))
warnings = set()
for i,s in enumerate(statuses):
    warn = ''
    if len(set(s)) != 1:
        s_ = [color("{:>4}".format(x)) for x in s]
        if 'LIVE' in s and ('EXC' in s or 'FAIL' in s):
            very_bad += 1
            warn = "\033[91;1m(!!!)\033[0m"
            for j, stat in enumerate(s):
                if stat == 'LIVE':
                    warnings.add(j + 1)
        bad += 1
        print("{:>3} ({:>4}) {}    {}".format(bad, i + 1, '  '.join(s_), warn))

# Write CSV
with open('results.csv', 'w', newline='') as csvfile:
    writer = csv.writer(csvfile, delimiter=',', quotechar='"',
            quoting=csv.QUOTE_MINIMAL)
    writer.writerow(['mut-id'] + dirs + ['warn'])
    for i, s in enumerate(statuses):
        warn = "0"
        if len(set(s)) != 1:
            if 'LIVE' in s and ('EXC' in s or 'FAIL' in s):
                warn = "1"
                for j, stat in enumerate(s):
                    if stat == 'LIVE':
                        warnings.add(j + 1)
            writer.writerow([i] + list(s) + [warn])

print("non-deterministic: {}/{} ({:>5}%)".format(bad, len(lines[0]) - 1, 100 * bad / (len(lines[0]) - 1)))
print(" live and failure: {}/{} ({:>5}%)".format(very_bad, len(lines[0]) - 1, 100 * very_bad / (len(lines[0]) - 1)))
