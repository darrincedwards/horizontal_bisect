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
particular defect was introduced.  That is, it has the same defect
isolation purpose as `git bisect`, but across a set of branches rather
than along a linear branch.

That is, traditional bisection (e.g. `git-bisect`, or a manual search based on
the method it implements) searches for the commit containing a defect along a linear history:
```text
A -- B -- C -- D -- E -- F
               ^
         defect introduced here
```

Horizontal bisection, by contrast, searches for the branch containing a new
branch out of an integration of several such branches:
```text
          integration
         /     |    \
        /      |     \
      feat1  feat2  feat3
               ^
       defect introduced here
```


## When is this useful?

This tool is expected to be most useful when:

- An integration branch merges many independently developed feature branches
- The integrated result exhibits a defect
- Each feature branch is believed to be individually coherent (the bug being sought, not an unrelated exception)
- Re-testing all the branch combinations manually would be expensive
- Traditional git bisect is not (yet) appropriate, because the branch containing the bug needs to be determined
  before a linear search can be performed

Since the general bisection principle is similar to that of linear ("vertical") bisection, the same rule
of thumb applies: if you only need to find the bug in a set of two or three branches, the advantage will
be slim, just as it would be in performing linear bisection on a set of two or three commits.  By ten
or so branches, though, the "log<sub>2</sub>" advantage should start to become noticeable (as in a linear search
on a set of ten or more commits).

Typical environments include:

- internal service-pack integration branches
- monorepos
- subsystem aggregation branches
- vendor import aggregation,
- release stabilization branches


## Current assumptions / limitations

- The integration branch was created via an octopus merge
- Component branches are independently testable
- The defect is reproducible in automated or repeatable testing

The first of these is planned to be addressed in a future release.
The others correspond to similar assumptions of linear bisection
(each commit represent a state that can be tested for exercising
the bug or not, as opposed to an exception thrown before the bug
location).


## Overview

The program is run iteratively, roughly similar to an interactive
rebase in git.  The first time it is run, it needs two arguments, the
"merged" branch being bisected, and the "base" branch from which the
components of the merged branch diverged (usually the current version
of the development branch that the integration branch under
examination will be merged into; or a previous "service pack", etc.).
After that it is run with no arguments, getting the information from
the control file horizontal_bisect_control.txt.

Each time it is run, the program
- selects another subset of the component branches for testing
- creates a temporary integration ("test") branch merging this subset of branches together
- and appends the new test branch name to the control file.

(If files were modified that require an extra step, like
recompilation, a message to that effect is generated.)  After running
the test branch, the user then edits the control file, placing a "p"
or "pass" in front of the test branch name if the defect is not
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

(The numbers in these branch names give the subset of feature branches included in the testing branch,
based on the order they're listed in at the top of the control file.)  A new branch sp_a_BISECT_0 is then
constructed, and you are asked to test and again mark the result of the test:

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
done.  As mentioned above, the advantage of bisection (log<sub>2</sub> of the
number of branches) will be more obvious with a larger number of
merged branches.  In the environment where this tool was originally
developed, we had service packs that typically included ten or a dozen
feature branches.  The application was an internal web service with a
relatively small number of pages; often a few of these branches
touched the same page, and occasionally it was not immediately obvious
which of those features had introduced a newly observed bug.  That is
the sort of situation for which this tool was designed.


## BUGS
- Currently it is assumed an octopus merge was done in order to create
  the integration branch being bisected.  This is arguably a wart rather
  than a bug, but it is planned to be addressed in a future release.
- No attempt is made to clean the horizontal_bisect_control.txt file (or
  backups of that generated by your editor), or to delete all the testing
  branches that get created.  Again, this is planned to be addressed in a
  future release.
