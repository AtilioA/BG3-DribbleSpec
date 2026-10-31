import json
from pathlib import Path

import pytest

from dribblespec_mutate import fnv1a32, main
from dribblespec_mutate.instrument import instrument
from test_instrument import _call, mutate_text


def test_source_hash_is_fnv1a32_and_ignores_crlf():
    assert fnv1a32(b"a") == "e40c292c"
    assert fnv1a32(b"x = 1\r\ny = 2\r\n") == fnv1a32(b"x = 1\ny = 2\n")

MCM_CONFIG = Path(r"C:\Users\AAD\Git\BG3-MCM\mutation.config.json")


LUA = Path("Mods/Folder/ScriptExtender/Lua")


def write_project(tmp_path: Path, **overrides) -> Path:
    lua = tmp_path / LUA / "Shared"
    lua.mkdir(parents=True)
    (lua / "B.lua").write_text("B = {}\nfunction B.f(x)\n  return x < 1\nend\n")
    (lua / "A.lua").write_text("A = {}\nfunction A.g(x) return x >= 2 end\n")
    (lua / "skip.txt").write_text("")
    (tmp_path / LUA.parent / "Config.json").write_text('{"RequiredVersion": 1, "ModTable": "M"}', encoding="utf-8-sig")
    config = tmp_path / "mutation.config.json"
    config.write_text(json.dumps({
        "mod": "Mods/Folder", "files": ["Shared/*.lua"], "testFilter": {"tags": ["x"]}, "ignoreCalls": [],
        **overrides,
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
                                  "replacement": "<=", "line": 3}
    assert set(plan) == {"runId", "modTable", "testFilter", "files", "mutants"}
    assert plan["modTable"] == "M"
    assert set(plan["files"][0]) == {"index", "path", "sourceHash", "targets"}
    assert plan["testFilter"] == {"tags": ["x"]}
    chunk = (run_dir / "2.lua").read_text()
    assert '__M.Cmp(3, "<", (x), (1))' in chunk


def test_list_fails_on_missing_mod(tmp_path, capsys):
    config = tmp_path / "c.json"
    config.write_text(json.dumps({"files": ["*.lua"]}))
    assert main(["list", "--config", str(config)]) == 1
    assert "'mod'" in capsys.readouterr().err


@pytest.mark.parametrize("key", ["modTable", "modDirectory", "ownerModuleUUID", "luaRoot"])
def test_list_rejects_a_cut_config_key(tmp_path, capsys, key):
    config = write_project(tmp_path, **{key: "x"})
    assert main(["list", "--config", str(config)]) == 1
    err = capsys.readouterr().err
    assert f"'{key}'" in err and "'mod'" in err


def test_list_fails_without_mod_config_json(tmp_path, capsys):
    config = write_project(tmp_path)
    (tmp_path / LUA.parent / "Config.json").unlink()
    assert main(["list", "--config", str(config)]) == 1
    assert "Config.json" in capsys.readouterr().err


@pytest.mark.parametrize("text", ["{not json", "[1]"])
def test_list_fails_on_a_bad_mod_config_json(tmp_path, capsys, text):
    config = write_project(tmp_path)
    (tmp_path / LUA.parent / "Config.json").write_text(text)
    assert main(["list", "--config", str(config)]) == 1
    assert "Config.json" in capsys.readouterr().err


def test_list_fails_without_mod_table(tmp_path, capsys):
    config = write_project(tmp_path)
    (tmp_path / LUA.parent / "Config.json").write_text('{"RequiredVersion": 1}')
    assert main(["list", "--config", str(config)]) == 1
    assert "'ModTable'" in capsys.readouterr().err


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
    assert plan["modTable"] == "BG3MCM"
    mcm = json.loads(MCM_CONFIG.read_text())
    lua_root = MCM_CONFIG.parent / mcm["mod"] / "ScriptExtender" / "Lua"
    ignore_calls = mcm["ignoreCalls"]
    for f in plan["files"]:
        source = (lua_root / f["path"]).read_bytes().decode()
        chunk = (run_dir / f"{f['index']}.lua").read_bytes().decode()
        assert (chunk.count("\n"), chunk.count("\r")) == (source.count("\n"), source.count("\r")), f["path"]
        lua.compile(chunk, "=" + f["path"])
        first_id = min((m["id"] for m in plan["mutants"] if m["file"] == f["index"]), default=1)
        expected = instrument(source.encode(), first_id=first_id, ignore_calls=ignore_calls).mutants
        assert [(m["id"], m["line"]) for m in plan["mutants"] if m["file"] == f["index"]] == \
            [(m.id, m.line) for m in expected], f["path"]
    assert "Shared/Helpers/Validators/ColorValidator.lua: 0 of 18 ignored\n" in out
    _check_color_validator(plan, lua_root, run_dir)


def _check_color_validator(plan, lua_root, run_dir):
    from conftest import Lua

    (f,) = [f for f in plan["files"] if f["path"].endswith("ColorValidator.lua")]
    source = (lua_root / f["path"]).read_bytes().decode()
    chunk = (run_dir / f"{f['index']}.lua").read_bytes().decode()
    first_id = min(m["id"] for m in plan["mutants"] if m["file"] == f["index"])
    # The plan has no columns, so the oracle takes the mutants from the same instrument call.
    mutants = instrument(source.encode(), first_id=first_id).mutants
    stub = "_Class = { Create = function() return {} end }; Validator = {}\n"
    inputs = ["{0, 1, 0.5, 1}", "{1, 1, 1, 1.0001}", "{-0, 0, 0, 0}", "{0, 0, 0}", '"x"']
    for m in [None] + mutants:
        oracle, subject = Lua(), Lua()
        text = mutate_text(source, m) if m else source
        oracle.run(stub); oracle.run(text)
        subject.run(stub); subject.run(source); subject.run(chunk)
        subject.runtime.a = m.id if m else 0
        for arg in inputs:
            got = _call(subject, "ColorValidator.Validate", None, subject.eval(arg))
            want = _call(oracle, "ColorValidator.Validate", None, oracle.eval(arg))
            assert got == want, (m, arg)


def test_list_fails_with_file_name_on_non_utf8_source(tmp_path, capsys):
    config = write_project(tmp_path)
    (tmp_path / LUA / "Shared" / "B.lua").write_bytes(b"x = '\xe9'\n")
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
