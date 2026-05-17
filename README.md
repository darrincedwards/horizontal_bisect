# horizontal_bisect

- Repository: https://github.com/darrincedwards/horizontal_bisect
- Files:
  - horizontal_bisect.pl
  - README.md
- Copyright: see copyright notice in horizontal_bisect.pl

Contributors: Please clone the repo and check out your new branch from **development**.

## Background

Bisection is a well-known tool for locating the commit within a linear
history (including git, within a single branch with no merges) in
which a defect was introduced. In a linear history of a hundred
commits, such a defect can be located by checking out and testing only
six or seven commits.

The script horizontal_bisect.pl attempts to perform "horizontal"
bisection; i.e., given an integration branch which merges together a
set of component branches (feature branches, subsystem branches,
vendor branches, etc.), find the one component branch in which a
particular defect was introduced.


## Overview

The program is run iteratively, roughly similar to an interactive
rebase in git.  The first time it is run, it needs two arguments, the
"merged" branch being bisected, and the "base" branch on which the
components of the merged branch were based (usually the preceding
integrated commit in the development branch, or a previous "service
pack", etc.).  After that it is run with no arguments, getting the
information from the control file horizontal_bisect_control.txt.

Each time it is run, the program selects the next appropriate subset
of the component branches for testing, constructs a new branch merging
this subset of branches together, and appends the test branch name to
the control file.  (If files were modified that require an extra step,
like recompilation, a message to that effect is generated.)  After
running the test branch, the user then edits the control file, placing
a "p" or "pass" in front of the test branch name if the defect is not
exhibited, and "f" or "fail" if it is.  (The test result indicators
are not case sensitive.)

Eventually such a test branch will be constructed with only one of the
original component branches in it; this will result in a single branch
containing the defect, and a validation branch containing all the
other component branches is constructed to verify that the defect only
occurs in that single branch.  (If not, the defect is presumably
caused by some interaction among the branches, or there are multiple
defects among the merged branches; more sophisticated debugging than
simple bisection will be required.)


## Example

Suppose we have a branch sp_a, that merges together three component branches
t001-add-func1, t002-add-func2, and t003-add-func3.  The history currently
looks like:

```text
*-.   ecc75ce (sp_a) Merge branches 't001-add-func1', 't002-add-func2' and 't003-add-func3' into sp_a
|\ \
| | * ec55edb (t003-add-func3) func3
| * | ba73ac5 (t002-add-func2) func2
| |/
* / b326045 (t001-add-func1) func1
|/
* c1aa866 func stubs
* 0d00b09 (master) initial commit
```

A defect is found in running sp_a.  Which branch introduced it?

```bash
horizontal_bisect.pl sp_a development
```

This will create a branch sp_a_BISECT_0_1 to be tested, merging t001-add-func1 and t002-add-func2.
It will also generate a file horizontal_bisect_control.txt, the last line of which
will be a line with the test branch name sp_a_BISECT_0_1.

After testing, that file is edited, and "pass" or "fail" (or just "p" or "f") are added to the
front of the line with the branch name.  Suppose this branch does fail the test; then the
horizontal_bisect_control.txt should, after you mark it, look like:

```text
#merged: sp_a
#base: development
t001-add-func1
t002-add-func2
t003-add-func3

f sp_a_BISECT_0_1
```

A new branch sp_a_BISECT_0 is then constructed, and you are asked to test and again mark the
result of the test:

```text
#merged: sp_a
#base: development
t001-add-func1
t002-add-func2
t003-add-func3

f sp_a_BISECT_0_1
p sp_a_BISECT_0
```

Since the combination of t001-add-func1 and t002-add-func2 failed, and
t001-add-func1 passed, the bug is expected to occur in t002-add-func2.
A validation branch sp_a_BISECT_1_VALIDATE is constructed to verify
this.

With only three branches, there were still two tests that needed to be
done.  The advantage of bisection (log_2 of the number of branches)
will be more obvious with a larger number of merged branches.  In the
environment where this tool was originally developed, we had service
packs that typically included ten or a dozen feature branches.  The
application was an internal web service with a relatively small number
of pages; often a few of these branches touched the same page, and
occasionally it was not immediately obvious which of those features
had introduced a newly observed bug.  That is the sort of situation
where it is hoped this tool might be of use.


## BUGS
- Currently it is assumed an octopus merge was done in order to create
  the integration branch being bisected.  This is arguably a wart rather
  than a bug, but it is planned to be addressed in a future release.
- No attempt is made to clean the horizontal_bisect_control.txt file (or
  backups of that generated by your editor), or to delete all the testing
  branches that get created.  Again, this is planned to be addressed in a
  future release.
