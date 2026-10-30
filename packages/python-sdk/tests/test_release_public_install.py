"""Inert wheels/installed trees and injected pip reports; no public runtime."""
import csv
from io import StringIO
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from python_release_cohort import verify_installed_release, verify_built_cohort


class ReleasePublicInstallTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='actql-public-wheel-component-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.wheels = self.root / 'wheels'; self.wheels.mkdir()
        self.version = '0.0.7rc1'  # Inert fixture, not a selected release version.
        self.plan = {'manifestSha256': 'a' * 64, 'targetId': 'python', 'artifacts': []}
        self.payloads = {}
        requirements = {'actql-sdk': ['httpx==0.28.1', 'rfc8785==0.1.4'],
            'actql-local-runtime': ['wasmtime==38.0.0'],
            'actql': ['actql-sdk==' + self.version, 'actql-local-runtime==' + self.version]}
        for name in ('actql-sdk', 'actql-local-runtime', 'actql'):
            package = name.replace('-', '_'); info = package + '-' + self.version + '.dist-info'
            tag = 'py3-none-macosx_11_0_arm64' if name == 'actql-local-runtime' else 'py3-none-any'
            payload = {package + '/__init__.py': b'"""Independent inert package; no product."""\n',
                info + '/METADATA': ('Metadata-Version: 2.1\nName: ' + name + '\nVersion: ' + self.version + '\n'
                    + ''.join('Requires-Dist: ' + value + '\n' for value in requirements[name])).encode(),
                info + '/WHEEL': ('Wheel-Version: 1.0\nGenerator: inert-fixture\nRoot-Is-Purelib: true\nTag: ' + tag + '\n').encode(),
                info + '/RECORD': b''}
            if name != 'actql-local-runtime':
                payload[package + '/__init__.pyi'] = b'# independent typed fixture\n'
                payload[package + '/py.typed'] = b''
            path = self.wheels / (package + '-' + self.version + '-' + tag + '.whl')
            with zipfile.ZipFile(path, 'w') as archive:
                for file, body in payload.items():
                    member = zipfile.ZipInfo(file); member.create_system = 3; member.external_attr = 0o100644 << 16
                    archive.writestr(member, body)
            body = path.read_bytes()
            self.plan['artifacts'].append({'name': name, 'version': self.version, 'path': str(path),
                'bytes': len(body), 'sha256': hashlib.sha256(body).hexdigest()})
            self.payloads[name] = payload

    def installed(self, entry='actql'):
        site = Path(tempfile.mkdtemp(prefix='site-', dir=self.root))
        names = ['actql-sdk'] if entry == 'actql-sdk' else list(self.payloads)
        rows = []
        for name in names:
            item = next(value for value in self.plan['artifacts'] if value['name'] == name)
            payload = dict(self.payloads[name]); info = name.replace('-', '_') + '-' + self.version + '.dist-info'
            payload[info + '/INSTALLER'] = b'pip\n'
            if name == entry: payload[info + '/REQUESTED'] = b''
            output = StringIO(); writer = csv.writer(output)
            for file in payload: writer.writerow([file, '', ''])
            payload[info + '/RECORD'] = output.getvalue().encode()
            for file, body in payload.items():
                path = site / file; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(body); path.chmod(0o644)
            rows.append({'metadata': {'name': name, 'version': self.version}, 'requested': name == entry,
                'is_direct': False, 'is_yanked': False, 'download_info': {
                    'url': 'https://files.pythonhosted.org/packages/inert/' + Path(item['path']).name,
                    'archive_info': {'hashes': {'sha256': item['sha256']}}}})
        report = site.parent / (site.name + '-report.json')
        body = {'version': '1', 'pip_version': '26.0', 'install': rows}; report.write_text(json.dumps(body))
        return site, report, body

    def audit(self, site, report, entry='actql'):
        return verify_installed_release(self.plan, report, entry, site)

    def test_complete_original_wheels_and_installed_bytes_match_without_importing_engines(self):
        site, report, _ = self.installed(); before = report.read_bytes()
        value = self.audit(site, report)
        self.assertEqual([row['name'] for row in value['payloads']], list(self.payloads))
        self.assertEqual(value['manifestSha256'], self.plan['manifestSha256'])
        self.assertEqual(report.read_bytes(), before)
        self.assertNotIn('actql_local_runtime', sys.modules)

    def test_sdk_only_has_no_product_or_runtime_distribution(self):
        site, report, _ = self.installed('actql-sdk')
        self.assertEqual([p['name'] for p in self.audit(site, report, 'actql-sdk')['payloads']], ['actql-sdk'])
        (site / 'actql_local_runtime').mkdir()
        # A package without a distribution record is also a forbidden Local namespace.
        (site / 'actql_local_runtime/__init__.py').write_text('# surplus runtime')
        with self.assertRaises(ValueError): self.audit(site, report, 'actql-sdk')

    def test_report_requires_exact_public_wheel_origin_hash_version_and_single_requested_entry(self):
        for field, changed in [('is_direct', True), ('is_yanked', True), ('requested', True)]:
            site, report, body = self.installed(); body['install'][0][field] = changed
            report.write_text(json.dumps(body))
            with self.assertRaises(ValueError): self.audit(site, report)
        for url in ['file:///old.whl', 'https://user:password@files.pythonhosted.org/a.whl',
                    'https://other.invalid/a.whl', 'https://files.pythonhosted.org/a.whl?token=private']:
            site, report, body = self.installed(); body['install'][0]['download_info']['url'] = url
            report.write_text(json.dumps(body))
            with self.assertRaises(ValueError): self.audit(site, report)
        for path, value in [('version', '0.0.8'), ('sha256', 'b' * 64)]:
            site, report, body = self.installed()
            if path == 'version': body['install'][0]['metadata']['version'] = value
            else: body['install'][0]['download_info']['archive_info']['hashes']['sha256'] = value
            report.write_text(json.dumps(body))
            with self.assertRaises(ValueError): self.audit(site, report)

    def test_missing_surplus_linked_or_changed_installed_payload_is_not_a_matching_original(self):
        for change in ('missing', 'surplus', 'link', 'bytes', 'mode'):
            site, report, _ = self.installed(); path = site / 'actql_sdk/__init__.py'
            if change == 'missing': path.unlink()
            elif change == 'surplus': (site / 'actql_sdk/foreign.py').write_text('# foreign')
            elif change == 'link':
                target = self.root / 'original.py'; shutil.copyfile(path, target); path.unlink(); path.symlink_to(target)
            elif change == 'mode': path.chmod(0o600)
            else: path.write_bytes(b'changed original')
            with self.assertRaises((ValueError, OSError)): self.audit(site, report)

    def test_changed_original_wheel_or_record_and_linked_site_cannot_supply_correspondence(self):
        site, report, _ = self.installed(); wheel = Path(self.plan['artifacts'][0]['path'])
        original = wheel.read_bytes(); wheel.write_bytes(b'x' * len(original))
        with self.assertRaises(ValueError): self.audit(site, report)
        wheel.write_bytes(original)
        record = site / ('actql_sdk-' + self.version + '.dist-info/RECORD')
        record.write_text(record.read_text() + '../foreign.py,,\n')
        with self.assertRaises(ValueError): self.audit(site, report)
        linked = self.root / 'linked-site'; linked.symlink_to(site)
        with self.assertRaises(ValueError): self.audit(linked, report)

    def test_original_and_fixed_flat_layout_share_the_existing_complete_wheel_reader(self):
        manifest = {'source_sha': 'a' * 40, 'package_version': self.version, 'platform': 'darwin-arm64',
            'core_abi': 78, 'host_capacity_sha256': None,
            **{key: 'b' * 64 for key in ['artifact_sha256', 'module_sha256', 'duckdb_sha256', 'image_sha256', 'engine_recipe_sha256']},
            **{key: False for key in ['runtime_executed', 'public_local_accepted', 'recovery_accepted', 'published']},
            'wheels': [{'distribution': row['name'], 'file': Path(row['path']).name,
                'bytes': row['bytes'], 'sha256': row['sha256']} for row in self.plan['artifacts']]}
        (self.root / 'cohort.json').write_text(json.dumps(manifest))
        old = verify_built_cohort(self.root, 'a' * 40, self.version)
        flat = self.root / 'fixed'; flat.mkdir(); shutil.copyfile(self.root / 'cohort.json', flat / 'cohort.json')
        for item in self.plan['artifacts']: shutil.copyfile(item['path'], flat / Path(item['path']).name)
        new = verify_built_cohort(flat, 'a' * 40, self.version, frozen_layout=True)
        self.assertEqual(old, new)
        (flat / Path(self.plan['artifacts'][0]['path']).name).unlink()
        with self.assertRaises(ValueError): verify_built_cohort(flat, 'a' * 40, self.version, frozen_layout=True)

    def test_real_pip_inert_entry_install_audits_actual_tree_but_local_report_is_not_public_acceptance(self):
        site = self.root / 'pip-site'; report = self.root / 'actual-private-pip-report.json'
        env = {key: value for key, value in os.environ.items() if not key.upper().startswith(('PIP_', 'PYTHON'))}
        env['PIP_CONFIG_FILE'] = os.devnull
        installer = self.root / 'installer'
        subprocess.run([sys.executable, '-I', '-B', '-m', 'venv', str(installer)], env=env,
                       check=True, capture_output=True, timeout=60)
        subprocess.run([str(installer / 'bin/python'), '-I', '-B', '-m', 'pip', '--isolated', 'install', '--no-index', '--no-deps',
            '--no-compile', '--find-links', str(self.wheels), '--target', str(site), '--report', str(report),
            'actql-sdk==' + self.version], env=env, check=True, capture_output=True, timeout=60)
        with self.assertRaises(ValueError): self.audit(site, report, 'actql-sdk')
        # Only this injected report changes. The original local pip report stays
        # retained; no actual public HTTP or product runtime is claimed.
        value = json.loads(report.read_bytes()); before = report.read_bytes()
        value['install'][0]['download_info']['url'] = 'https://files.pythonhosted.org/packages/inert/' + Path(self.plan['artifacts'][0]['path']).name
        injected = self.root / 'injected-public-report.json'; injected.write_text(json.dumps(value))
        self.assertEqual(len(self.audit(site, injected, 'actql-sdk')['payloads']), 1)
        self.assertEqual(report.read_bytes(), before)
