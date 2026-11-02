"""Audit local normal-cohort wheel bytes inside the isolated consumer interpreter."""
from __future__ import annotations
import argparse
import hashlib
from importlib import metadata
import importlib.util
import json
from pathlib import Path, PurePosixPath
import sys
import zipfile


def audit(cohort_directory: Path, report_path: Path) -> dict:
    cohort = json.loads((cohort_directory / 'cohort.json').read_text())
    report = json.loads(report_path.read_text())
    expected = {item['distribution']: item for item in cohort['wheels']}
    if set(expected) != {'actql', 'actql-sdk', 'actql-local-runtime'}:
        raise AssertionError('Expected the complete normal cohort')
    installed = {item['metadata']['name'].lower().replace('_', '-'): item for item in report['install']}
    count = 0
    for name, item in expected.items():
        wheel = cohort_directory / 'wheels' / item['file']
        body = wheel.read_bytes()
        if len(body) != item['bytes'] or hashlib.sha256(body).hexdigest() != item['sha256']:
            raise AssertionError('Wheel bytes differ from the producer cohort')
        resolution = installed[name]
        if (resolution['download_info']['url'] != wheel.resolve().as_uri()
                or resolution['download_info']['archive_info']['hashes'].get('sha256') != item['sha256']
                or resolution.get('is_direct') is not True):
            raise AssertionError('Installer did not select the exact local wheel')
        distribution = metadata.distribution(name)
        if distribution.version != cohort['package_version']:
            raise AssertionError('Installed version differs from producer')
        site = Path(distribution.locate_file('')).resolve()
        if Path(sys.prefix).resolve() not in site.parents or sys.prefix == sys.base_prefix:
            raise AssertionError('Consumer is not an independent virtual environment')
        with zipfile.ZipFile(wheel) as zipped:
            expected_files = set()
            for member in zipped.infolist():
                if member.is_dir():
                    continue
                path = PurePosixPath(member.filename)
                if path.is_absolute() or '..' in path.parts or '.data' in path.parts[0] or path.suffix == '.pth':
                    raise AssertionError('Unsupported wheel member layout')
                if member.filename.endswith('.dist-info/RECORD'):
                    continue  # pip legitimately rewrites installation paths/hashes.
                actual = site / member.filename
                if actual.is_symlink() or site not in actual.resolve().parents or actual.read_bytes() != zipped.read(member):
                    raise AssertionError(f'Installed payload differs: {member.filename}')
                expected_files.add(member.filename)
                count += 1
            for top in ('actql', 'actql_sdk', 'actql_local_runtime'):
                if any(value.startswith(top + '/') for value in expected_files):
                    actual_files = {p.relative_to(site).as_posix() for p in (site / top).rglob('*') if p.is_file()}
                    if actual_files != {value for value in expected_files if value.startswith(top + '/')}:
                        raise AssertionError('Unexpected installed package payload')
                    spec = importlib.util.find_spec(top)
                    if spec is None or Path(spec.origin).resolve() != site / top / '__init__.py':
                        raise AssertionError('Public import does not resolve to the installed wheel')
    return {'wheel_distributions': sorted(expected), 'verified_members': count, 'prefix': sys.prefix}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(audit(args.cohort, args.report)))
