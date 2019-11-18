"""
After running experiments, we want to analyze the consistency within each tools
running, and across the two different runs of the tool. This analyzes results
and prints results to stdout
"""
from sys import argv
from os import path as osp
from os import walk
from math import log

NO_RESULT=-1
SUCCESS=0
TIMEOUT=1
ERROR=2

def entropy(samples, space=None):
    if space is None:
        space = {TIMEOUT, ERROR, SUCCESS}
    n = len(samples)
    counts = {}
    for x in space:
        counts[x] = 0
    for y in samples:
        counts[y] += 1
    H = 0.0
    for y in set(samples):
        p = counts[y] / n
        H -= p * log(p) / log(2)
    return H

def usage():
    print("\033[1mUsage:\033[0m python3 {} java7_root java8_root".format(argv[0]))
    print("     \033[1m- java7_root:\033[0m root of analysis using major-java7")
    print("     \033[1m- java8_root:\033[0m root of analysis using major plugin with Java 8")

class Experiment:
    def __init__(self, root):
        self.root = root
        # self.data represents all the data collected in this experiment. It is
        # a nested dictionary, that maps the PID to a dictionary that maps all
        # a dictionary mapping each VID to data on each trial of that VID.
        self.data = {}  # {pid -> {vid -> {trial -> [trial data]}}}
        self.read_in_results()

    def read_in_results(self):
        """
        Read the results from this experiment
        """
        failed = self.read_file_lines('failed.csv')[1:]
        completed = self.read_file_lines('completed.csv')[1:]
        started = self.read_file_lines('started.csv')[1:]
        status = self.read_file_lines('status.csv')[1:]
        success = self.read_file_lines('success.csv')[1:]
        timedout = self.read_file_lines('timedout.csv')[1:]

        data = self.data
        for line in started:
            items = line.split(',')
            assert len(items) == 3
            pid, vid, trial = items
            vid_map = data.setdefault(pid, {})
            trial_map = vid_map.setdefault(vid, {})
            trial_map.setdefault(trial,
                    {
                        'return-val'   : None,
                        'result-pretty': None,
                        'start'        : None,
                        'end'          : None,
                        'result-code'  : NO_RESULT
                     })

        for line in status:
            items = line.split(',')
            assert len(items) == 6
            pid, vid, trial, start, end, res = items
            res = int(res)
            trial_map = data[pid][vid][trial]
            trial_map['start'] = start
            trial_map['end'] = end
            trial_map['return-val'] = res
            trial_map['result-pretty'] = self._pretty_status(trial_map['return-val'])
            trial_map['result-code'] = SUCCESS if res == 0 else TIMEOUT if res == 124 else ERROR

        return data

    def _pretty_status(self, code):
        if code == 0:
            return 'SUCCESS'
        if code == 124:
            return 'TIMEOUT'
        else:
            return 'ER({:^3})'.format(code)

    def read_file_lines(self, *path):
        """
            Read in a file line by line from a path relative to the root of the
           experiment. All newlines are stripped from the end of each line
        """
        with open(osp.join(self.root, *path)) as f:
            return [l.strip('\n') for l in f.readlines()]

    def print(self, pids=None, color=True):

        data = self.data
        keys = data.keys()
        if pids is None:
            pids = keys
        for pid in pids:
            if pid in keys:
                subj = data[pid]
                for vid in subj.keys():
                    codes = []
                    for tid in subj[vid].keys():
                        trial = subj[vid][tid]
                        if color:
                            pretty = trial['result-pretty']
                            code = "\033[1;32m" if pretty == 'SUCCESS' else "\033[1;34m" if pretty == "TIMEOUT" else "\033[1;31m"
                            status = "{}{}\033[0m".format(code, trial['result-pretty'])
                        else:
                            status = "{}".format(trial['result-pretty'])
                        print("{}-{:<3} ({}) {}-{}: {}".format(pid, vid, tid, trial['start'], trial['end'], status))
                        codes.append(trial['result-code'])
                    H = entropy(codes)
                    print("H={}".format(H))

    def compare(self, other):
        data1 = self.data
        data2 = other.data

        pids = set(data1.keys()).union(set(data2.keys()))
        result = {}
        result['flat'] = []
        for pid in pids:
            if pid not in data1:
                result[pid] = "No data for {} in {}".format(pid, self.root)
                continue
            elif pid not in data2:
                result[pid] = "No data for {} in {}".format(pid, other.root)
                continue
            pid_map = result.setdefault(pid, {})
            vid_map1 = data1[pid]
            vid_map2 = data2[pid]
            vids = set(vid_map1.keys()).union(set(vid_map2.keys()))
            for vid in vids:
                if vid not in vid_map1.keys():
                    pid_map[vid] = "No data for {}-{} in {}".format(pid, vid, self.root)
                    continue
                if vid not in vid_map2.keys():
                    pid_map[vid] = "No data for {}-{} in {}".format(pid, vid, other.root)
                    continue
                vid_map = pid_map.setdefault(vid, {})
                tid_map1 = vid_map1[vid]
                tid_map2 = vid_map2[vid]
                vid_map['exp1'] = tid_map1
                vid_map['exp2'] = tid_map2
                trials1 = [tid_map1[n] for n in tid_map1] 
                trials2 = [tid_map2[n] for n in tid_map2]
                trials = trials1 + trials2
                codes1 = [x['result-code'] for x in trials1]
                codes2 = [x['result-code'] for x in trials2]
                codes_all = codes1 + codes2
                H1 = entropy(codes1)
                H2 = entropy(codes2)
                H_all = entropy(codes_all)
                vid_map['all'] = trials
                stats = vid_map['stats'] = {}
                stats['H1'] = H1
                stats['H2'] = H2
                stats['H'] = H_all
                flat = [pid, vid, codes1, codes2, H1, H2, H_all]
                result['flat'].append(flat)
        return result

if __name__ == '__main__':
    if len(argv) != 3:
        usage()

    java7_root = argv[1]
    java8_root = argv[2]

    exp_java7 = Experiment(java7_root)
    exp_java8 = Experiment(java8_root)

    exp_java7.read_in_results()

def test():
    e1 = Experiment('/scratch/benku/major-version-tests/major1')
    e2 = Experiment('/scratch/benku/major-version-tests/major2')
    r = e1.compare(e2)
    return r
