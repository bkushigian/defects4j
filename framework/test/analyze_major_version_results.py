"""
After running experiments, we want to analyze the consistency within each tools
running, and across the two different runs of the tool. This analyzes results
and prints results to stdout
"""
from sys import argv
from os import path as osp
from os import walk

def usage():
    print("\033[1mUsage:\033[0m python3 {} java7_root java8_root".format(argv[0]))
    print("     \033[1m- java7_root:\033[0m root of analysis using major-java7")
    print("     \033[1m- java8_root:\033[0m root of analysis using major plugin with Java 8")

if len(argv) != 3:
    usage()

java7_root = argv[1]
java8_root = argv[2]

class Experiment:
    def __init__(self, root):
        self.root = root
        # self.data represents all the data collected in this experiment. It is
        # a nested dictionary, that maps the PID to a dictionary that maps all
        # a dictionary mapping each VID to data on each trial of that VID.
        self.data = {}  # {pid -> {vid -> {trial -> [trial data]}}}

    def read_in_results(self):
        started = self.read_file_lines('started.csv')
        completed = self.read_file_lines('completed.csv')
        status = self.read_file_lines('status.csv')
        failed = self.read_file_lines('failed.csv')

        data = self.data
        for line in started:
            items = line.split(',')
            assert len(items) == 3
            pid, vid, trial = items
            vid_map = data.setdefault(pid, {})
            trial_map = vid_map.setdefault(vid, {})
            trial_map.setdefault(trial,
                    { 
                        'result': None,
                        'start' : None, 
                        'end'   : None,
                     })
        for line in status:
            items = line.split(',')
            assert len(items) == 6
            pid, vid, trial, start, end, res = items
            trial_map = data[pid][vid][trial]
            trial_map['start'] = start
            trial_map['end'] = end
            trial_map['result'] = res


    def read_file_lines(self, *path):
        """
            Read in a file line by line from a path relative to the root of the
           experiment. All newlines are stripped from the end of each line
        """
        with open(osp.join(self.root, *path)) as f:
            return [l.strip('\n') for l in f.readlines()]

    def analyze_intra_experiment_data(self):
        """
        Detect non-determinism within this experiment
        """
        pass


exp_java7 = Experiment(java7_root)
exp_java8 = Experiment(java8_root)

exp_java7.read_in_results()
