"""Read the qualified I5 SDK-only wheel; no normal cohort or runtime claim."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from python_interface_inventory import wheel_source_correspondence

wheel = Path('/private/tmp/actql-i5-pack-S62Bdf/wheels/actql_sdk-0.0.0.dev0-py3-none-any.whl')
expected = 'c1eedc1b9723cc46485b3b7332ef92a5675c0ba95c821f89ec3e9366b21bdbc3'
before = wheel.stat()
if not wheel.is_file() or wheel.is_symlink() or before.st_size != 338850:
    raise ValueError('Unexpected retained SDK wheel identity')
if hashlib.sha256(wheel.read_bytes()).hexdigest() != expected:
    raise ValueError('Changed retained SDK wheel')
source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
result = wheel_source_correspondence(ROOT, wheel, 'packages/python-sdk/pyproject.toml', source)
after = wheel.stat()
if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
    raise ValueError('Retained SDK wheel changed during read')
result.update({'artifact_sha256': expected,
               'artifact_qualification': 'I5 SDK-only component; original 12747 Source plus test-driver-only flag; not pristine three-wheel cohort',
               'originals': 'R/i5-language-parity-d0ccdb956/manifest.json',
               'new_installed_E2E': 0})
output = ROOT / '_build/interface-evidence/retained-sdk-wheel.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
