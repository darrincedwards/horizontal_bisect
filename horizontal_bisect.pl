#!/usr/bin/perl
use strict;
use warnings;

# Copyright 2026, Darrin C. Edwards, darrin.c.edwards@gmail.com.
# Free to use and redistribute.  No warranty for any purpose.
# If a modified copy is distributed, please modify the name of the file and include author information here.

# Bisection is a well-known tool for locating the commit within a linear
# history (including git, within a single branch with no merges) in which a
# defect was introduced. In a (linear) history of a hundred commits,
# such a defect can be located by checking out and testing only six or
# seven commits.

# This script attempts to perform "horizontal" bisection; i.e., given a branch
# which merges together a set of component branches, find the one component branch
# in which a particular defect is introduced.

# The program is run iteratively; the first time it needs two arguments, the "merged"
# branch being bisected, and the "base" branch on which the components of the merged branch
# were based (usually the preceding "service pack").  After that it is run with no arguments,
# getting the information from the control file horizontal_bisect_control.txt.

# Each time it is run, the program selects the next appropriate subset of the component
# branches for testing, constructs a new branch merging this subset of branches together,
# and appends the test branch name to the control file.
# (If files were modified that require an extra step, like recompilation, a message to that effect
# is generated; see NOTE: below.)  After running the test branch, the user
# then edits the control file, placing a "p" or "pass" in front of the test branch name
# if the defect is not exhibited, and "f" or "fail" if it is.  (The test result indicators
# are not case sensitive.)

# Eventually such a test branch will be constructed with only one of the original
# component branches in it; this will result in a single branch containing the defect,
# and a validation branch containing all the other component branches is constructed to
# verify that the defect only occurs in that single branch.  (If not, the defect is presumably
# caused by some interaction among the branches, or there are multiple defects among the
# merged branches; more sophisticated debugging than simple bisection will be required.)

# NOTE: The check_flagged_paths function allows you to list paths for which an extra
# step, such as reconfiguration or recompilation, might be needed.  For example, in the
# specific environment where this tool was developed, there was a Java subsystem which
# would need recompiling if changes had been made to any files in a "pcng" subdirectory.
# You may have different such requirements, which can be included in the @flagged_paths list;
# or you might not need any at all, in which case the @flagged_paths list can be left empty.


# User-configurable variables
my $control_filename = 'horizontal_bisect_control.txt';  # Add a path to e.g. keep the control file out of your repo
my @flagged_paths = (  # See NOTE above
  # 'pcng',  # check any files in a directory
  # 'others/just in case.txt',  # specific files need a full path if in a subdirectory
);


use constant {
    PASS => 'pass',
    FAIL => 'fail',
};

my %result_flag = ('p' => PASS,
                   'f' => FAIL,
                  );

my @source_types = qw(merged base);
my %source_branch;
@source_branch{@source_types} = ('') x @source_types;


(my $progname = $0) =~ s{^.*/}{};

my $usage = <<EOU;
Usage:
   $progname [merged_branch base_branch]
Performs horizontal bisection on merged_branch, the components of which were based off
of base_branch.  If no arguments are supplied, continues a bisection already in progress.
EOU

if (@ARGV && ($ARGV[0] eq '-h' || $ARGV[0] eq '--help')) {
  warn $usage;
  exit;
}

@source_branch{@source_types} = @ARGV;
my @branches;
my %index;
my %result;

if (defined $source_branch{'merged'} && defined $source_branch{'base'}) {
  my $merge_msg = `git log $source_branch{'merged'} -n 1 --oneline --grep='Merge'`;
  @branches = $merge_msg =~ /'(.*?)'/g;

  @index{@branches}   = 0..$#branches;
  @result{@branches} = (FAIL) x @branches;

  open my $control_file, '>', $control_filename;
  print $control_file <<EOF;
@{[join("\n", map {"#$_: $source_branch{$_}"} @source_types)]}
@{[join("\n", @branches)]}

EOF
  close $control_file;
} else {
  if (@ARGV) {
    warn qq{$usage\n(Ignoring single argument "$ARGV[0]".)\n};
  }

  open my $control_file, '<', $control_filename or die "No arguments supplied, but $control_filename not found.\n";

  # first segment is the list of component branches in the merged branch
  while (<$control_file>) {
    chomp;
    if (/^#(\w+): (.*)$/) {
      $source_branch{$1} = $2 if exists $source_branch{$1};
      next;
    }
    last if /^$/;
    push @branches, $_;
  }

  @index{@branches}   = 0..$#branches;
  @result{@branches} = (FAIL) x @branches;

  # second segment is the bisecting branches that have been attempted so far, each preceded by 'pass' or 'fail'
  while (my $line = <$control_file>) {
    chomp($line);
    my ($result, $branch) = split(' ', $line, 2);

    my $flag = lc(substr($result, 0, 1));
    if (!exists $result_flag{$flag}) {
      die "Unrecognized test result $result in control file (expected '@{[PASS]}' or '@{[FAIL]}'), aborting";
    } else {
      $result = $result_flag{$flag};
    }

    my @current_set = get_branches($branch);

    @result{@current_set} = ($result) x @current_set;

    if ($result eq FAIL) {
      my %current_set;
      @current_set{@current_set} = (1) x @current_set;
      my @complement = grep {!$current_set{$_}} @branches;
      @result{@complement} = (PASS) x @complement; # this overwrites a given name with PASS multiple times, but the code is much simpler than
                                                   # if we kept explicit track at each stage of the previous test set and test set complement
    }
  }

  close $control_file;
}

my @current_set = grep {$result{$_} eq FAIL} @branches;
if (@current_set == 1) {
  my $defect_branch = $current_set[0];
  my @complement = grep {$_ ne $defect_branch} @branches;
  my $validation_branch = make_branch_name($defect_branch) . '_VALIDATE';
  system('git', 'checkout', '-b', $validation_branch, $source_branch{'base'});
  system('git', 'merge', @complement);
  print <<EOF;
Defect appears to be in branch $defect_branch.
A validation branch $validation_branch has been constructed to verify the defect (or an unrelated one) does not occur outside the defect branch.
EOF
  check_flagged_paths($validation_branch);
  exit;
}
my $new_test_size = int(@current_set / 2 + 0.5);
my @new_test_set = @current_set[0..$new_test_size-1];

my $new_test_branch = make_branch_name(@new_test_set);
system('git', 'checkout', '-b', $new_test_branch, $source_branch{'base'});
system('git', 'merge', @new_test_set);
print <<EOF;
Ready to test for defect in component branches of $new_test_branch.
EOF
check_flagged_paths($new_test_branch);

open my $control_file, '>>', $control_filename;
print $control_file "$new_test_branch\n";
close $control_file;

sub get_branches {
  my $test_branch = shift;

  my @indices;
  if ($test_branch =~ /^$source_branch{'merged'}_BISECT_((?:\d+_)*\d+)$/) {
    @indices = split('_', $1);
  } else {
    die "Unparseable test branch name $test_branch in control file, aborting";
  }

  return @branches[@indices];
}

sub make_branch_name {
  my @test_set = @_;

  my @indices = @index{@test_set};

  return "$source_branch{'merged'}_BISECT_" . join('_', @indices);
}

sub check_flagged_paths {
  my $branch = shift;

  foreach my $flagged_path (@flagged_paths) {
    my $diff = `git diff $source_branch{'base'} $branch --name-only -- "$flagged_path"`;

    if ($diff) {
      print "Flagged path '$flagged_path' was modified in branch $branch; check for steps such as recompilation before testing.\n";
    }
  }
}
