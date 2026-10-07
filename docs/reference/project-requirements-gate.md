# Project Requirements Gate

Every pull request is checked against three TIG project requirements:
documentation parity, broad deployability, and test coverage. The
[criteria](../../.github/project-requirements/criteria.md) define what passes.
The check is done by the
[Project Requirements workflow](../../.github/workflows/project-requirements.yml),
which reports a `Project Requirements` commit status that branch protection
can require.

The criteria are not in a `REVIEW.md` file, so Devin's general PR review does
not apply them. They are used only by this gate.

## How it works

1. A pull request is opened, updated, reopened, or marked ready for review.
   Drafts are skipped until they are ready.
2. The workflow checks out the **base** branch and runs
   `.github/scripts/project_requirements_gate.py`. The script and criteria
   always come from the base branch, so a PR cannot change the rules it is
   judged by. A change to the criteria takes effect once it merges.
3. The script lists the changed files, adds path-based hints (for example,
   `tig-cli/src/` changed but `tig-cli/tests/` did not), and starts a Devin
   session through the Devin API. The session reviews the diff against the
   criteria and returns a structured verdict of `pass`, `concern`, or `fail`
   for each requirement.
4. The script posts the verdicts as a single PR comment, which is updated
   in place on later runs, and sets the commit status:

   | Result | Status |
   | --- | --- |
   | No `fail` verdicts (`pass` or `concern` only) | success |
   | Any `fail` verdict | failure |
   | No verdict (API error, timeout, malformed output) | error |
   | Waived by a maintainer | success |

A run takes as long as the Devin session, usually several minutes. Pushing
again cancels the previous run.

## Waiving a finding

A maintainer can waive a `fail` by adding the `requirements-waived` label. The
gate then passes with the status `Waived by @<login>`. Only a label added by
someone with write, maintain, or admin access counts. Explain the waiver in
the PR discussion. Removing the label runs the full evaluation again.

## Setup

Repository settings (**Settings > Secrets and variables > Actions**):

| Name | Kind | Required | Purpose |
| --- | --- | --- | --- |
| `DEVIN_API_KEY` | Secret | Yes | Devin service user API key with permission to create sessions. |
| `DEVIN_ORG_ID` | Variable (or secret) | Yes | Devin organization ID (`org-...`) that sessions run in. Read from the variable first, then the secret. |
| `DEVIN_API_URL` | Variable | No | Devin API base URL. Defaults to `https://api.devin.ai`; set it for dedicated deployments. |
| `PROJECT_REQUIREMENTS_MAX_ACU` | Variable | No | ACU limit per session. |
| `PROJECT_REQUIREMENTS_WAIVER_LABEL` | Variable | No | Waiver label name. Defaults to `requirements-waived`. |

Then:

1. Create the `requirements-waived` label.
2. In the branch protection rules (or ruleset) for `develop` and `master`,
   require the `Project Requirements` status check.

To re-run the gate, re-run the workflow from the Actions tab, or start it
manually with **Run workflow** and the PR number.

## Changing the gate

- Edit the criteria in `.github/project-requirements/criteria.md`. Keep the
  three requirement names in step with `REQUIREMENTS` in the gate script.
- The script uses only the Python standard library. Its tests are in
  `.github/scripts/tests/` and run in the
  [Project Requirements Gate Tests](../../.github/workflows/project-requirements-tests.yml)
  workflow:

  ```bash
  python -m pytest .github/scripts/tests
  ```
