#!/usr/bin/env python3

from sys import argv, stdin

OTHER='OTHER'
LINE_NUMS_ONLY='LINE_NUMS_ONLY'
FAILING_TEST_HEADER='FAILING_TEST_HEADER'

STATUS_DIFF = 'diff'
STATUS_NEW_FILE = 'new_file'
STATUS_DELETED_FILE = 'deleted_file'

def split_into_files(diff):
    """Given a diff, split it into files"""
    print("Splitting diff into files and hunks:")
    print(diff[: min(len(diff), 120)])

    files = []
    line_iter = iter(diff.split('\n'))
    hunks = None
    body = None
    try:
        while True:
            line = next(line_iter)
            if line.startswith('diff --git'):
                _, _, aname, bname = line.strip().split()
                status = 'diff'

                line = next(line_iter)
                if line.startswith('deleted file mode'):
                    line = next(line_iter)
                    status = STATUS_DELETED_FILE
                elif line.startswith('new file mode'):
                    line = next(line_iter)
                    status = STATUS_NEW_FILE
                assert line.startswith('index'), "Found line: {}".format(line)
                line = next(line_iter)
                assert line.startswith('---'), "Found line: {}".format(line)
                line = next(line_iter)
                assert line.startswith('+++'), "Found line: {}".format(line)
                hunks = []
                file = {'a': aname, 'b': bname, 'hunks': hunks, 'status': status}
                files.append(file)

            elif line.startswith('@@'):
                body = []
                idx = line.index('@@', 2) + 2
                header, line = line[:idx], line[idx:]
                body.append(line)
                hunk = {'header': header, 'body': body}
                hunks.append(hunk)

            elif line.startswith(' ') or line.startswith('+') or line.startswith('-'):
                assert body is not None
                body.append(line)

            elif line.strip():
                raise RuntimeError("Unrecognized line: {}".format(line))

    except StopIteration as e:
        print('done')
        print(e)
    print("Found {} files".format(len(files)))
    return files

def classify_hunk(hunk):
    """Classify a diff's hunk:
    - LINE_NUMS_ONLY
    - OTHER
    """

    removed = []
    added = []
    for line in hunk['body']:
        if not line:
            continue
        elif line.startswith(' '):
            continue
        elif line.startswith('-'):
            removed.append(line)
        elif line.startswith('+'):
            added.append(line)
        else:
            raise RuntimeError("Unrecognized hunk line: '{}'".format(line.strip('\n')))

    if len(removed) == len(added):
        if len(removed):
            for left, right in zip(removed, added):
                left, right = left[1:], right[1:]   # Strip +/-
                for start, (a, b) in enumerate(zip(left, right)):
                    if a != b:
                        break
                for end, (a, b) in enumerate(zip(left[::-1], right[::-1])):
                    if a != b:
                        break
                # print("left:  {}".format(left))
                # print("right: {}".format(right))
                # print("diff:  [{},-{}]".format(start, end))
                # print("    {}".format(left[start:-end]))
                # print("    {}".format(right[start:-end]))
                try:
                    l1 = int(left[start:-end])
                    l2 = int(right[start:-end])
                    return LINE_NUMS_ONLY
                except ValueError as e:
                    print(e)
                    return OTHER
        else:
            raise RuntimeError("Empty diff!")
    elif removed and removed[0].startswith('-##') and removed[0].strip().endswith('##'):
        return FAILING_TEST_HEADER

    return OTHER

def main():
    print(argv)
    piped = ''.join([line for line in stdin])
    if piped:
        files = split_into_files(piped)
        for file in files:
            to_print = []
            status = file['status']
            if status is not STATUS_DIFF:
                print('-' * 80)
                print("Diff from files:", file['a'], file['b'])
                print("    Status", status)
                print("    Num Hunks:", len(file['hunks']))
                continue

            for i, hunk in enumerate(file['hunks']):
                classification = classify_hunk(hunk)
                if classification is OTHER:
                    to_print.append((classification, hunk))

            if to_print:
                print('-' * 80)
                print("Diff from files:", file['a'], file['b'])
                print("    Status", status)
                print("    Num Hunks:", len(file['hunks']))
                for classification, hunk in to_print:
                    print('+-' * 40)
                    print()
                    print('>>> Hunk {}:'.format(i), hunk['header'])
                    print('\n'.join(hunk['body'][:min(20, len(hunk['body']))]))
                    print()


main()
