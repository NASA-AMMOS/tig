import io
import json
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import project_requirements_gate as gate  # noqa: E402

PASS = {"verdict": "pass", "summary": "ok", "findings": []}
FAIL = {
    "verdict": "fail",
    "summary": "README not updated",
    "findings": [{"file": "tig-cli/README.md", "line": 12, "issue": "flag | missing",
                  "fix": "Document --fast"}],
}
GOOD_OUTPUT = {"documentation_parity": PASS, "broad_deployability": PASS,
               "test_coverage": PASS, "summary": "All good"}


def make_config(tmp_path, **overrides):
    criteria = tmp_path / "criteria.md"
    criteria.write_text("# TIG Project Requirements\n")
    env = {
        "GITHUB_REPOSITORY": "NASA-AMMOS/tig",
        "PR_NUMBER": "7",
        "GITHUB_TOKEN": "gh-token",
        "GITHUB_RUN_ID": "99",
        "DEVIN_API_KEY": "devin-key",
        "DEVIN_ORG_ID": "org-1",
        "CRITERIA_PATH": str(criteria),
        "DEVIN_TIMEOUT_MINUTES": "1",
        "DEVIN_POLL_SECONDS": "10",
    }
    env.update(overrides)
    return gate.Config.from_env(env)


class FakeApi:
    """Routes gate HTTP calls to canned GitHub and Devin responses."""

    def __init__(self, sessions=None, labels=(), draft=False, labeler="maintainer",
                 permission="write", comments=()):
        self.sessions = list(sessions or [])
        self.labels = labels
        self.draft = draft
        self.labeler = labeler
        self.permission = permission
        self.comments = list(comments)
        self.calls = []

    def statuses(self):
        return [body for method, url, body in self.calls if "/statuses/" in url]

    def __call__(self, method, url, token, body=None):
        self.calls.append((method, url, body))
        if "api.devin.ai" in url:
            assert token == "devin-key"
            if method == "POST":
                return {"session_id": "s1", "url": "https://app.devin.ai/sessions/s1"}, {}
            return self.sessions.pop(0), {}
        assert token == "gh-token"
        path = url.split("/repos/NASA-AMMOS/tig", 1)[1]
        if path == "/pulls/7":
            return {
                "html_url": "https://github.com/NASA-AMMOS/tig/pull/7",
                "draft": self.draft,
                "base": {"ref": "develop"},
                "head": {"sha": "abcdef1234567"},
                "labels": [{"name": n} for n in self.labels],
            }, {}
        if path.startswith("/pulls/7/files"):
            return [{"filename": "tig-cli/src/tig_cli/cli.py"}], {}
        if path.startswith("/issues/7/events"):
            return [{"event": "labeled", "label": {"name": "requirements-waived"},
                     "actor": {"login": self.labeler}}], {}
        if path.startswith("/collaborators/"):
            return {"permission": self.permission}, {}
        if path.startswith("/issues/7/comments") and method == "GET":
            return self.comments, {}
        return {}, {}


def make_gate(config, api):
    return gate.GitHub(config, api), gate.Devin(config, api, sleep=lambda s: None)


def test_config_reports_missing_settings():
    with pytest.raises(gate.GateError, match="DEVIN_API_KEY, DEVIN_ORG_ID"):
        gate.Config.from_env({"GITHUB_REPOSITORY": "o/r", "PR_NUMBER": "1",
                              "GITHUB_TOKEN": "t"})


def test_config_defaults(tmp_path):
    config = make_config(tmp_path)
    assert config.devin_api_url == "https://api.devin.ai"
    assert config.waiver_label == "requirements-waived"
    assert config.max_acu is None
    assert config.run_url == "https://github.com/NASA-AMMOS/tig/actions/runs/99"


def test_precheck_hints_flag_untested_undocumented_cli_change():
    hints = gate.precheck_hints(["tig-cli/src/tig_cli/cli.py"])
    assert any("tests" in h for h in hints)
    assert any("README" in h for h in hints)


def test_precheck_hints_quiet_when_docs_and_tests_change():
    files = ["tig-cli/src/tig_cli/cli.py", "tig-cli/tests/test_cli.py", "tig-cli/README.md"]
    assert gate.precheck_hints(files) == []


def test_precheck_hints_generator_and_demos():
    hints = gate.precheck_hints(["terrain-intelligence-generator/Dockerfile",
                                 "demo-panorama-mosaic.sh"])
    assert any("terrain-intelligence-generator" in h for h in hints)
    assert any("docs/demos" in h for h in hints)
    assert gate.precheck_hints(["terrain-intelligence-generator/README.md"]) == []


def test_build_prompt_includes_scope_and_truncates_files(tmp_path):
    config = make_config(tmp_path)
    pr = {"html_url": "u", "base": {"ref": "develop"}, "head": {"sha": "abc"}}
    files = [f"f{i}" for i in range(gate.MAX_FILES_IN_PROMPT + 5)]
    prompt = gate.build_prompt(config, pr, files, ["hint one"], "CRITERIA TEXT")
    assert "ONLY the three requirements" in prompt
    assert "untrusted" in prompt
    assert "git fetch origin pull/7/head" in prompt
    assert "- hint one" in prompt
    assert "and 5 more" in prompt
    assert prompt.rstrip().endswith("CRITERIA TEXT")


@pytest.mark.parametrize("output", [
    None,
    "not json object",
    {"documentation_parity": PASS, "broad_deployability": PASS},
    {**GOOD_OUTPUT, "test_coverage": {"verdict": "maybe", "summary": "", "findings": []}},
    {**GOOD_OUTPUT, "test_coverage": {"verdict": "pass", "summary": "", "findings": "x"}},
])
def test_validate_output_rejects_malformed(output):
    with pytest.raises(gate.GateError):
        gate.validate_output(output)


def test_overall_state_and_description():
    results = gate.validate_output({**GOOD_OUTPUT, "test_coverage": FAIL})
    assert gate.overall_state(results) == "failure"
    assert gate.status_description(results) == "2 pass, 0 concern, 1 fail"
    concern = {**PASS, "verdict": "concern"}
    assert gate.overall_state(gate.validate_output({**GOOD_OUTPUT, "test_coverage": concern})) \
        == "success"


def test_render_comment_escapes_and_lists_findings():
    results = gate.validate_output({**GOOD_OUTPUT, "documentation_parity": FAIL})
    body = gate.render_comment(results, "Needs docs", "abcdef1234", ["hint"],
                               "https://s", "https://r", "requirements-waived")
    assert body.startswith(gate.COMMENT_MARKER)
    assert "## Project Requirements: FAIL" in body
    assert "`tig-cli/README.md:12`: flag \\| missing **Fix:** Document --fast" in body
    assert "Evaluated at `abcdef1`" in body
    assert "`requirements-waived` label" in body


def test_run_pass_sets_success_and_creates_comment(tmp_path):
    config = make_config(tmp_path)
    api = FakeApi(sessions=[
        {"status": "running", "status_detail": "working", "structured_output": None},
        {"status": "running", "status_detail": "finished", "structured_output": GOOD_OUTPUT},
    ])
    assert gate.run(config, *make_gate(config, api)) == 0
    create = next(b for m, u, b in api.calls if m == "POST" and "api.devin.ai" in u)
    assert create["structured_output_required"] is True
    assert create["structured_output_schema"] == gate.OUTPUT_SCHEMA
    assert "max_acu_limit" not in create
    states = [s["state"] for s in api.statuses()]
    assert states == ["pending", "pending", "success"]
    assert all(s["context"] == "Project Requirements" for s in api.statuses())
    assert any(m == "POST" and u.endswith("/issues/7/comments") for m, u, b in api.calls)


def test_run_fail_updates_existing_comment(tmp_path):
    config = make_config(tmp_path, DEVIN_MAX_ACU="5")
    api = FakeApi(
        sessions=[{"status": "exit", "status_detail": None,
                   "structured_output": json.dumps({**GOOD_OUTPUT, "test_coverage": FAIL})}],
        comments=[{"id": 3, "body": "other"}, {"id": 4, "body": gate.COMMENT_MARKER + " old"}],
    )
    assert gate.run(config, *make_gate(config, api)) == 1
    assert api.statuses()[-1]["state"] == "failure"
    create = next(b for m, u, b in api.calls if m == "POST" and "api.devin.ai" in u)
    assert create["max_acu_limit"] == 5
    assert any(m == "PATCH" and u.endswith("/issues/comments/4") for m, u, b in api.calls)
    assert not any(m == "POST" and u.endswith("/issues/7/comments") for m, u, b in api.calls)


@pytest.mark.parametrize("session", [
    {"status": "error", "status_detail": "error", "structured_output": None},
    {"status": "running", "status_detail": "finished", "structured_output": None},
    {"status": "exit", "status_detail": None, "structured_output": {"summary": "partial"}},
])
def test_run_reports_error_when_no_verdict(tmp_path, session):
    config = make_config(tmp_path)
    api = FakeApi(sessions=[session])
    assert gate.run(config, *make_gate(config, api)) == 1
    assert api.statuses()[-1]["state"] == "error"
    comment = next(b for m, u, b in api.calls if m == "POST" and u.endswith("/issues/7/comments"))
    assert "Project Requirements: ERROR" in comment["body"]


def test_wait_for_output_times_out(tmp_path):
    config = make_config(tmp_path)
    working = {"status": "running", "status_detail": "working", "structured_output": None}
    api = FakeApi(sessions=[working] * 10)
    ticks = iter(range(0, 1000, 30))
    devin = gate.Devin(config, api, sleep=lambda s: None, clock=lambda: next(ticks))
    with pytest.raises(gate.GateError, match="Timed out after 1 min"):
        devin.wait_for_output("s1")


def test_run_honours_maintainer_waiver(tmp_path):
    config = make_config(tmp_path)
    api = FakeApi(labels=["requirements-waived"])
    assert gate.run(config, *make_gate(config, api)) == 0
    assert api.statuses() == [{"state": "success", "context": "Project Requirements",
                               "description": "Waived by @maintainer",
                               "target_url": config.run_url}]
    assert not any("api.devin.ai" in u for m, u, b in api.calls)


def test_run_ignores_waiver_without_write_access(tmp_path):
    config = make_config(tmp_path)
    api = FakeApi(labels=["requirements-waived"], permission="read", sessions=[
        {"status": "exit", "status_detail": None, "structured_output": GOOD_OUTPUT}])
    assert gate.run(config, *make_gate(config, api)) == 0
    assert any("api.devin.ai" in u for m, u, b in api.calls)
    assert api.statuses()[-1]["description"] == "3 pass, 0 concern, 0 fail"


def test_run_skips_drafts(tmp_path):
    config = make_config(tmp_path)
    api = FakeApi(draft=True)
    assert gate.run(config, *make_gate(config, api)) == 0
    assert api.statuses() == []


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload
        self.headers = {"X-Test": "1"}

    def read(self):
        return json.dumps(self.payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def http_error(code):
    return gate.urllib.error.HTTPError("https://x", code, "err", {}, io.BytesIO(b"boom"))


def test_http_json_retries_server_errors(monkeypatch):
    outcomes = [http_error(502), gate.urllib.error.URLError("reset"), FakeResponse({"ok": 1})]
    requests = []

    def fake_urlopen(request, timeout):
        requests.append(request)
        outcome = outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    monkeypatch.setattr(gate.urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setattr(gate.time, "sleep", lambda s: None)
    data, headers = gate.http_json("POST", "https://x", "tok", {"a": 1})
    assert data == {"ok": 1}
    assert headers == {"X-Test": "1"}
    assert len(requests) == 3
    assert requests[0].get_header("Authorization") == "Bearer tok"
    assert requests[0].get_header("Content-type") == "application/json"


@pytest.mark.parametrize("errors, calls", [([http_error(404)], 1),
                                           ([http_error(500)] * 2, 2)])
def test_http_json_raises_on_client_error_or_exhausted_retries(monkeypatch, errors, calls):
    seen = []

    def fake_urlopen(request, timeout):
        seen.append(request)
        raise errors[len(seen) - 1]

    monkeypatch.setattr(gate.urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setattr(gate.time, "sleep", lambda s: None)
    with pytest.raises(gate.GateError, match="returned HTTP .*: boom"):
        gate.http_json("GET", "https://x", "tok", attempts=2)
    assert len(seen) == calls


WORKFLOW = Path(__file__).resolve().parents[2] / "workflows" / "project-requirements.yml"


def resolve_workflow_env(name, context):
    """Evaluate a workflow env entry of the form `${{ a.B || c.D }}` against `context`."""
    match = re.search(rf"^\s+{name}: \$\{{\{{(.+?)\}}\}}\s*$", WORKFLOW.read_text(), re.MULTILINE)
    assert match, f"{name} not found in {WORKFLOW.name}"
    for ref in match.group(1).split("||"):
        scope, key = ref.strip().split(".", 1)
        value = context.get(scope, {}).get(key, "")
        if value:
            return value
    return ""


@pytest.mark.parametrize("context, expected", [
    ({"vars": {"DEVIN_ORG_ID": "org-var"}}, "org-var"),
    ({"secrets": {"DEVIN_ORG_ID": "org-secret"}}, "org-secret"),
    ({"vars": {"DEVIN_ORG_ID": "org-var"}, "secrets": {"DEVIN_ORG_ID": "org-secret"}}, "org-var"),
])
def test_workflow_org_id_accepts_variable_or_secret(tmp_path, context, expected):
    org_id = resolve_workflow_env("DEVIN_ORG_ID", context)
    assert make_config(tmp_path, DEVIN_ORG_ID=org_id).devin_org_id == expected


def test_workflow_org_id_missing_from_both_is_a_config_error(tmp_path):
    org_id = resolve_workflow_env("DEVIN_ORG_ID", {})
    with pytest.raises(gate.GateError, match="Missing configuration: DEVIN_ORG_ID"):
        make_config(tmp_path, DEVIN_ORG_ID=org_id)


def test_report_setup_error_comments_and_sets_error_status(tmp_path):
    env = {"GITHUB_REPOSITORY": "NASA-AMMOS/tig", "PR_NUMBER": "7", "GITHUB_TOKEN": "gh-token",
           "GITHUB_RUN_ID": "99", "DEVIN_API_KEY": "devin-key"}
    api = FakeApi()
    gate.report_setup_error(env, "Missing configuration: DEVIN_ORG_ID", api)
    status = api.statuses()[-1]
    assert status["state"] == "error"
    assert status["description"] == "Gate error: Missing configuration: DEVIN_ORG_ID"
    comment = next(b for m, u, b in api.calls if m == "POST" and u.endswith("/issues/7/comments"))
    assert "Project Requirements: ERROR" in comment["body"]
    assert "Missing configuration: DEVIN_ORG_ID" in comment["body"]
    assert gate.SETUP_DOC in comment["body"]


def test_report_setup_error_without_github_access_only_warns(capsys):
    api = FakeApi()
    gate.report_setup_error({"PR_NUMBER": "7"}, "Missing configuration: GITHUB_TOKEN", api)
    assert api.calls == []
    assert "Could not report the configuration error" in capsys.readouterr().out


def test_report_setup_error_survives_github_failure():
    def failing_http(method, url, token, body=None):
        raise gate.GateError("GET pulls returned HTTP 403")

    env = {"GITHUB_REPOSITORY": "NASA-AMMOS/tig", "PR_NUMBER": "7", "GITHUB_TOKEN": "gh-token"}
    gate.report_setup_error(env, "Missing configuration: DEVIN_ORG_ID", failing_http)


@pytest.mark.parametrize("overrides, removed, error", [
    ({}, "DEVIN_ORG_ID", "Missing configuration: DEVIN_ORG_ID"),
    ({}, "DEVIN_API_KEY", "Missing configuration: DEVIN_API_KEY"),
    ({"DEVIN_MAX_ACU": "oops"}, None, "invalid literal for int()"),
])
def test_main_reports_configuration_errors_on_the_pr(monkeypatch, tmp_path, overrides, removed,
                                                      error):
    env = {"GITHUB_REPOSITORY": "NASA-AMMOS/tig", "PR_NUMBER": "7", "GITHUB_TOKEN": "gh-token",
           "GITHUB_RUN_ID": "99", "DEVIN_API_KEY": "devin-key", "DEVIN_ORG_ID": "org-1",
           "CRITERIA_PATH": str(tmp_path / "criteria.md"), **overrides}
    for name in ("DEVIN_API_URL", "DEVIN_MAX_ACU", "DEVIN_TIMEOUT_MINUTES",
                 "DEVIN_POLL_SECONDS", "GITHUB_API_URL", "GITHUB_SERVER_URL"):
        monkeypatch.delenv(name, raising=False)
    for name, value in env.items():
        monkeypatch.setenv(name, value)
    if removed:
        monkeypatch.delenv(removed)
    api = FakeApi()
    assert gate.main(api) == 1
    status = api.statuses()[-1]
    assert status["state"] == "error"
    assert status["description"].startswith("Gate error: ")
    assert error in status["description"]
    comment = next(b for m, u, b in api.calls if m == "POST" and u.endswith("/issues/7/comments"))
    assert error in comment["body"]
    assert gate.SETUP_DOC in comment["body"]
    assert not any("api.devin.ai" in u for m, u, b in api.calls)
