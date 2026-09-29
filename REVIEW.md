# Review Guidelines

## Scope of these guidelines

**Perform the full default review first.** Everything the standard review
normally covers still applies to every pull request: correctness, bugs, edge
cases, security, performance, error handling, readability, and style. Nothing in
this file replaces, narrows, or lowers the priority of that review.

The sections below are **additional project requirements** for the Terrain
Intelligence Generator (TIG). They reflect project policy for open-source
contributions, and they are evaluated on top of the default review. A PR that
passes these requirements can still have default-review findings, and the
reverse is also true. Report both.

Each additional requirement gets a **verdict**. If any requirement is
**Fail**, request changes. The PR should not be approved until the finding is
resolved or a maintainer explicitly waives it in the PR discussion.

| # | Requirement | A failing PR... |
| --- | --- | --- |
| 1 | [Documentation parity](#1-documentation-parity) | changes user-facing behavior without updating the docs that describe it. **Blocking.** |
| 2 | [Broad deployability](#2-broad-deployability) | ties a feature to one organization's infrastructure, credentials, or niche toolchain. |
| 3 | [Test coverage](#3-test-coverage) | adds a fix without a regression test, or new capability without nominal and off-nominal tests. |

---

## 1. Documentation parity

**Goal:** a user reading the docs after the merge sees behavior that matches the
code. If a PR changes what users see or do and the related documentation was
not updated in the same PR, **reject it** (request changes).

### Step 1: Decide whether the change is user-facing

Treat a change as user-facing if it does any of the following:

- Adds, removes, renames, or changes the default of a `tig` CLI option,
  subcommand, config-file key (`config.toml` / `tig.toml`), or environment
  variable (`tig-cli/src/tig_cli/cli.py`, `config.py`, `entry.py`, `shim.py`).
- Changes how `tig` finds or talks to a container runtime, translates paths,
  mounts directories, reuses containers, handles X11/GUI tools, or builds from
  source (`runtime.py`, `path_translator.py`, `container.py`, `engine.py`,
  `broker.py`, `server.py`, `build.py`).
- Changes what is in a container image, its tags, build arguments, bundled
  VICAR version, calibration contents, or entrypoint
  (`terrain-intelligence-generator/**`).
- Changes the arguments, inputs, outputs, or product names of a `demo-*.sh`,
  `fetch-calibration.sh`, or `find-calibration.sh` script.
- Changes an example under `examples/` (DAGs, wrappers, Kubernetes manifests,
  `env.example`, `docker-compose.yml`).
- Changes install requirements: supported Python versions, OS/architecture
  support, runtime prerequisites, or `pyproject.toml` dependencies.
- Changes an error message, exit code, or log output that users or scripts
  are likely to rely on.

Changes that are usually **not** user-facing: internal refactors with identical
behavior, test-only changes, CI-only changes that do not alter published
artifacts, and comment/typo fixes. Say so explicitly in the review when you
decide a change is not user-facing, and why.

### Step 2: Check the matching documentation

For each user-facing change, confirm the PR updates the relevant files. Common
mappings:

| Area changed | Documentation to check |
| --- | --- |
| `tig-cli/**` (options, config, env vars, behavior) | `tig-cli/README.md` |
| Container images, tags, build args, VISOR/fullfeatured variants | `terrain-intelligence-generator/README.md` |
| `demo-*.sh` scripts | Matching page in `docs/demos/`, and `docs/demos/commands.md` if commands changed |
| Calibration scripts / calibration data | `docs/reference/calibration-data.md`, `docs/demos/downloading-visor-data.md` |
| `vicario` | `docs/reference/vicario.md`, `terrain-intelligence-generator/docker/VICARIO.md` |
| `examples/<name>/**` | `examples/<name>/README.md` |
| Install / prerequisites / platform support | `docs/getting-started.md`, `docs/install-macos.md`, `QUICKSTART.md`, `README.md` |
| New capability, component, or workflow | `README.md` (Key Capabilities), `docs/README.md` index, `docs/architecture/components.md` |
| Agent workflows that exercise the changed behavior | Relevant `.agents/skills/*/SKILL.md` |

Also check that:

- Commands, flags, file paths, and sample output shown in the docs actually
  match the new code (stale examples count as missing docs).
- New pages are linked from `docs/README.md` or the nearest index.
- Removed or renamed behavior is removed from the docs, not just added to.

### Verdict

- **Pass** — not user-facing, or user-facing and the matching docs are updated
  and accurate.
- **Fail (blocking)** — user-facing and the docs were not updated, or the
  updates are inaccurate or incomplete. List each missing or stale doc file and
  what it needs to say.

---

## 2. Broad deployability

**Goal:** TIG is contributed as open source for use by many missions,
organizations, and projects. Features should work for a broad set of users
without forcing them onto one site's infrastructure or a niche toolchain. New
tools can be introduced when they are genuinely needed, but the burden they put
on consumers must be justified. This is a judgment call on a sliding scale;
explain the reasoning rather than applying it mechanically.

### Flag these (likely Fail unless justified)

- **Hard-coded site specifics:** internal hostnames, URLs, IPs, registry paths,
  bucket names, mount points, usernames, or file-system layouts belonging to
  one organization (for example, JPL-internal hosts or paths) instead of being
  configurable with a sensible public default.
- **Credentials or access that only one organization has:** a feature that only
  works behind a specific VPN, SSO, or private artifact store, with no public
  or configurable path.
- **Single-runtime assumptions:** code that only works with one container
  runtime when TIG supports several (`docker`, `podman`, `nerdctl`, `finch`),
  or that assumes root, a specific socket path, or disabled SELinux.
- **Single-platform assumptions:** code that silently breaks on Linux, macOS
  (Intel or Apple Silicon), or a supported Python version (3.9-3.12) without
  a documented reason and a clear error message.
- **Mandatory heavy infrastructure:** making Kubernetes, Airflow, MinIO,
  RabbitMQ, a specific cloud provider, or a specific CI system a requirement
  for core functionality. These belong in `examples/` or optional integrations,
  not in the core CLI or image.
- **Mission-locked behavior:** baking one mission's instrument names,
  calibration layout, or product conventions into general-purpose code paths
  when it could be parameterized.
- **New required dependencies** (Python packages, system packages, external
  services) that are niche, unmaintained, license-incompatible with Apache-2.0,
  or pulled in for a small convenience.

### Usually acceptable

- New tooling that is optional, isolated behind a flag or config key, or
  confined to `examples/` with its own README.
- Defaults tuned for a common case, as long as users can override them through
  a CLI option, config key, or environment variable.
- Mission-specific support (for example, a new VISOR calibration variant) that
  is additive and does not change behavior for other missions.

### Verdict

- **Pass** — generic and configurable, or any specific tooling is optional and
  documented.
- **Concern** — works broadly but adds friction (for example, a new dependency
  or an assumption that should be configurable). Describe the friction and
  suggest a more portable alternative; not blocking on its own.
- **Fail** — the feature is effectively unusable outside a specific
  organization, deployment, or toolchain. Explain who is excluded and what
  change would make it portable.

---

## 3. Test coverage

**Goal:** every behavioral change is covered by an automated test at some
appropriate level: unit, integration, or image/pipeline.

### What each kind of change needs

- **Bug fixes** must include a test that reproduces the specific condition
  that exposed the bug and fails without the fix. A generic test that happens
  to pass is not enough; the review should name the triggering condition and
  point to the test that exercises it.
- **New capability** needs both:
  - **Nominal tests** — the expected, happy-path behavior.
  - **Off-nominal tests** — invalid or missing inputs, bad configuration,
    missing container runtime or image, unwritable paths, permission errors,
    empty or malformed data, timeouts, and boundary values. Check that errors
    are clear and exit codes are correct, not just that nothing crashed.
- **Changed behavior** needs existing tests updated to assert the new behavior.
  Deleting or weakening assertions to make a test pass is a red flag; call it
  out.
- **Refactors** with no behavior change can rely on existing tests, but the
  review should confirm those tests actually exercise the refactored code.

### Where tests live

| Area changed | Expected test location |
| --- | --- |
| `tig-cli/src/tig_cli/*.py` | `tig-cli/tests/test_<module>.py` (unit, runs in CI via `.github/workflows/test.yml`); container-backed behavior in `tig-cli/tests/integration/` with `@pytest.mark.integration` |
| Container images (`terrain-intelligence-generator/docker`, `visor`, `fullfeatured`) | `terrain-intelligence-generator/test-*-image.sh` scripts run by the build/publish workflows |
| VICAR product outputs / pipelines | `terrain-intelligence-generator/test-product-pipeline.sh`, `test-release-regression.sh`, or a focused script like `test-marsirough-abend.sh` |
| Demo and calibration scripts | The matching image or calibration test script, or `.github/workflows/calibration-demo.yml` |
| `examples/**` | At minimum a documented, reproducible manual test in the example README or its `.agents/skills/` skill; automated tests preferred |

Also check that:

- New tests are actually run by CI. If a new test script or path is not covered
  by any workflow's `paths:` filter or job steps, flag it.
- Tests are deterministic and do not depend on private data, private network
  access, or a specific developer machine (this ties back to criterion 2).
- Unit tests mock the container runtime rather than requiring one; tests that
  need a real runtime are marked `integration`.

### Verdict

- **Pass** — fixes have targeted regression tests; new capability has nominal
  and off-nominal tests; tests run in CI.
- **Concern** — tests exist but miss notable off-nominal paths or are not wired
  into CI. List the missing cases.
- **Fail** — a fix has no regression test, new capability has no tests, or
  tests were weakened to pass.

---

## Reporting

Report the default review findings as usual. Then add a separate
**Project Requirements** section with a summary table of the three verdicts,
followed by details for anything that is not **Pass**:

```markdown
### Project Requirements

| Requirement | Verdict | Notes |
| --- | --- | --- |
| 1. Documentation parity | Fail | `--foo` added to `tig` but not documented in `tig-cli/README.md` |
| 2. Broad deployability | Pass | New option is configurable with a public default |
| 3. Test coverage | Concern | No off-nominal test for an unreadable config file |
```

For each project-requirement finding, cite the file and line, explain why it
matters to users, and suggest a concrete fix (the doc section to update, the
configuration hook to add, or the test case to write). Do not drop or shorten
default-review findings to make room for this section.
