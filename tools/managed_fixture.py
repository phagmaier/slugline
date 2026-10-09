"""Managed disk fixtures for disposable native-process probes (ADR 0068).

The caller owns a temporary XDG root. Product project creation stays in Rust.
"""
import json
from pathlib import Path
import uuid


def create_project(work: Path, name: str, source: bytes) -> Path:
    library = work / "data/slugline/library"
    identity = uuid.uuid4().hex
    project = library / f"{name}--{identity}"
    project.mkdir(parents=True)
    (project / "versions").mkdir()
    script = project / "script.fountain"
    script.write_bytes(source)
    (project / "project.json").write_text(json.dumps({
        "version": 1, "id": identity, "name": name,
        "archived": False, "pinned_entities": [],
    }))
    config = work / "config/slugline"
    config.mkdir(parents=True, exist_ok=True)
    (config / "prefs.json").write_text(json.dumps({"library_dir": str(library)}))
    return script
