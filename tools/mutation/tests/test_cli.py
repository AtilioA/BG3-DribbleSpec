import json
from pathlib import Path

import pytest

from dribblespec_mutate import fnv1a32, main
from test_instrument import _call, mutate_text


def test_source_hash_is_fnv1a32_and_ignores_crlf():
    assert fnv1a32(b"a") == "e40c292c"
    assert fnv1a32(b"x = 1\r\ny = 2\r\n") == fnv1a32(b"x = 1\ny = 2\n")

MCM_CONFIG = Path(r"C:\Users\AAD\Git\BG3-MCM\mutation.config.json")


def write_project(tmp_path: Path) -> Path:
    lua = tmp_path / "Lua" / "Shared"
    lua.mkdir(parents=True)
    (lua / "B.lua").write_text("B = {}\nfunction B.f(x)\n  return x < 1\nend\n")
    (lua / "A.lua").write_text("A = {}\nfunction A.g(x) return x >= 2 end\n")
    (lua / "skip.txt").write_text("")
    config = tmp_path / "mutation.config.json"
    config.write_text(json.dumps({
        "modTable": "M", "modDirectory": "M", "ownerModuleUUID": "uuid",
        "luaRoot": "Lua", "files": ["Shared/*.lua"], "testFilter": {"tags": ["x"]}, "ignoreCalls": [],
    }))
    return config


def test_list_prints_mutants_and_writes_plan_and_chunks(tmp_path, capsys):
    config = write_project(tmp_path)
    assert main(["list", "--config", str(config)]) == 0
    lines = capsys.readouterr().out.splitlines()
    assert lines[:4] == [
        "Shared/A.lua:2 RelationalBoundary >= -> >",
        "Shared/A.lua:2 RelationalBoundary >= -> <",
        "Shared/B.lua:3 RelationalBoundary < -> <=",
        "Shared/B.lua:3 RelationalBoundary < -> >=",
    ]
    (run_dir,) = (tmp_path / ".dribblespec-mutation" / "DribbleSpecMutation").iterdir()
    plan = json.loads((run_dir / "plan.json").read_text())
    assert [(f["index"], f["path"], f["targets"]) for f in plan["files"]] == [
        (1, "Shared/A.lua", ["A.g"]), (2, "Shared/B.lua", ["B.f"]),
    ]
    assert [m["id"] for m in plan["mutants"]] == [1, 2, 3, 4]
    assert plan["mutants"][2] == {"file": 2, "id": 3, "operator": "RelationalBoundary", "original": "<",
                                  "replacement": "<=", "line": 3, "column": 12}
    assert plan["testFilter"] == {"tags": ["x"]}
    chunk = (run_dir / "2.lua").read_text()
    assert plan["files"][1]["patchPath"].endswith("/2.lua")
    assert '__M.Cmp(3, "<", (x), (1))' in chunk


def test_list_fails_on_missing_config_field(tmp_path, capsys):
    config = tmp_path / "c.json"
    config.write_text(json.dumps({"modTable": "M"}))
    assert main(["list", "--config", str(config)]) == 1
    assert "'modDirectory'" in capsys.readouterr().err


@pytest.mark.skipif(not MCM_CONFIG.exists(), reason="MCM repo not present")
def test_list_on_mcm_validators_includes_spike_mutants(tmp_path, capsys, lua):
    assert main(["list", "--config", str(MCM_CONFIG), "--out", str(tmp_path)]) == 0
    out = capsys.readouterr().out
    for line in [
        "Shared/Helpers/Validators/SliderIntValidator.lua:16 RelationalBoundary >= -> >",
        "Shared/Helpers/Validators/SliderIntValidator.lua:16 RelationalBoundary <= -> <",
        "Shared/Helpers/Validators/FloatUtils.lua:17 RelationalBoundary < -> <=",
        "Shared/Helpers/Validators/FloatUtils.lua:20 RelationalBoundary > -> >=",
    ]:
        assert line + "\n" in out
    (run_dir,) = (tmp_path / "DribbleSpecMutation").iterdir()
    plan = json.loads((run_dir / "plan.json").read_text())
    lua_root = MCM_CONFIG.parent / json.loads(MCM_CONFIG.read_text())["luaRoot"]
    for f in plan["files"]:
        source = (lua_root / f["path"]).read_bytes().decode()
        chunk = (tmp_path / f["patchPath"]).read_bytes().decode()
        assert (chunk.count("\n"), chunk.count("\r")) == (source.count("\n"), source.count("\r")), f["path"]
        lua.compile(chunk, "=" + f["path"])
    assert "Shared/Helpers/Validators/ColorValidator.lua: 0 of 4 ignored\n" in out
    _check_color_validator(plan, lua_root, tmp_path)


def _check_color_validator(plan, lua_root, out_dir):
    from conftest import Lua

    (f,) = [f for f in plan["files"] if f["path"].endswith("ColorValidator.lua")]
    source = (lua_root / f["path"]).read_bytes().decode()
    chunk = (out_dir / f["patchPath"]).read_bytes().decode()
    mutants = [m for m in plan["mutants"] if m["file"] == f["index"]]
    stub = "_Class = { Create = function() return {} end }; Validator = {}\n"
    inputs = ["{0, 1, 0.5, 1}", "{1, 1, 1, 1.0001}", "{-0, 0, 0, 0}", "{0, 0, 0}", '"x"']
    for m in [None] + mutants:
        oracle, subject = Lua(), Lua()
        text = mutate_text(source, type("M", (), m)) if m else source
        oracle.run(stub); oracle.run(text)
        subject.run(stub); subject.run(source); subject.run(chunk)
        subject.runtime.a = m["id"] if m else 0
        for arg in inputs:
            got = _call(subject, "ColorValidator.Validate", None, subject.eval(arg))
            want = _call(oracle, "ColorValidator.Validate", None, oracle.eval(arg))
            assert got == want, (m, arg)


def test_list_fails_with_file_name_on_non_utf8_source(tmp_path, capsys):
    config = write_project(tmp_path)
    (tmp_path / "Lua" / "Shared" / "B.lua").write_bytes(b"x = '\xe9'\n")
    assert main(["list", "--config", str(config)]) == 1
    assert "Shared/B.lua: not valid UTF-8" in capsys.readouterr().err


def test_list_never_reuses_a_run_directory(tmp_path, capsys):
    config = write_project(tmp_path)
    assert main(["list", "--config", str(config)]) == 0
    assert main(["list", "--config", str(config)]) == 0
    runs = list((tmp_path / ".dribblespec-mutation" / "DribbleSpecMutation").iterdir())
    assert len(runs) == 2
    for run in runs:
        assert json.loads((run / "plan.json").read_text())["runId"] == run.name
