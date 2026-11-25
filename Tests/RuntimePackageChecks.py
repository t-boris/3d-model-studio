"""Run the shipped installer on tiny vendor-shaped archives, offline on either Mac."""
import base64
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

resources = Path("Providers/Runtime").resolve()
installer = resources / "install.sh"
rows = [line.split("\t") for line in (resources / "artifacts.tsv").read_text().splitlines()]
assert {(row[0], row[1]) for row in rows} == {
    (p, arch) for p in ("Codex", "Claude", "Antigravity") for arch in ("arm64", "x86_64")
}

# Substitute only the download in this test shell. The shipped script still
# chooses the artifact, verifies its bytes, extracts it and configures Python.
driver = """
function /usr/bin/curl() {
    [[ "${!#}" == "$FIXTURE_URL" ]] || return 1
    /bin/cp "$FIXTURE_ARCHIVE" archive
}
source "$SCRIPT" "$@"
"""

for provider, arch, url, published_hash in rows:
    with tempfile.TemporaryDirectory() as temp:
        directory = Path(temp)
        inputs = directory / "Runtime"
        shutil.copytree(resources, inputs)
        wheel_file = inputs / f"requirements-{arch}.txt"
        wheels = wheel_file.read_text().splitlines()[1:]
        assert all(" @ https://files.pythonhosted.org/" in line and ".whl --hash=sha256:" in line for line in wheels)
        assert any("google_antigravity-0.1.24" in line and arch in line for line in wheels)
        triple = ("aarch64" if arch == "arm64" else arch) + "-apple-darwin"
        member, destination = {
            "Codex": (f"package/vendor/{triple}/bin/codex", "native/bin/codex"),
            "Claude": ("package/claude", "claude"),
            "Antigravity": ("python/bin/python3", "python/bin/python3")
        }[provider]
        archive = directory / "fixture.tgz"
        with tarfile.open(archive, "w:gz") as bundle:
            item = tarfile.TarInfo(member)
            double = b'#!/bin/sh\n/usr/bin/printf "%s\\n" "$@" > pip-args\n'
            item.size = len(double)
            item.mode = 0o755
            bundle.addfile(item, io.BytesIO(double))
        stage = directory / "stage"
        stage.mkdir()
        command = ["/bin/bash", "-c", driver, "double", provider, str(inputs), arch]
        env = {"SCRIPT": str(installer), "FIXTURE_ARCHIVE": str(archive), "FIXTURE_URL": url,
               "PATH": "/usr/bin:/bin", "HOME": str(stage)}
        # The production digest rejects the fixture before it can execute.
        assert subprocess.run(command, cwd=stage, env=env).returncode == 12
        assert not (stage / destination).exists()
        data = archive.read_bytes()
        digest = (hashlib.sha256(data).hexdigest() if provider == "Antigravity"
                  else base64.b64encode(hashlib.sha512(data).digest()).decode())
        manifest = inputs / "artifacts.tsv"
        manifest.write_text(manifest.read_text().replace(published_hash, digest))
        subprocess.run(command, cwd=stage, env=env, check=True)
        assert os.access(stage / destination, os.X_OK)
        if provider == "Antigravity":
            args = (stage / "pip-args").read_text().splitlines()
            assert {"--require-hashes", "--only-binary=:all:", "--no-deps", "--no-index"} <= set(args)
            assert args[-2:] == ["-r", str(wheel_file)]
            assert (stage / "antigravity.py").read_bytes() == (resources / "antigravity.py").read_bytes()
        print(f"{provider} {arch}: pinned archive, integrity rejection and staged installation passed.")
