"""Independent uv-resolution/installed-tree controls; no public runtime."""
import copy
import csv
from io import StringIO
import json
from pathlib import Path
import sys
from unittest import TestCase
from unittest.mock import patch

import test_release_public_install as fixtures
from python_release_cohort import verify_installed_release


def toml_value(value):
    if type(value) in (str, int, bool):
        return json.dumps(value)
    if type(value) is list:
        return '[' + ', '.join(toml_value(item) for item in value) + ']'
    if type(value) is dict:
        return '{' + ', '.join(json.dumps(key) + ' = ' + toml_value(item) for key, item in value.items()) + '}'
    raise ValueError('Unsupported independent fixture value')


class ReleaseUvInstallTests(TestCase):
    def setUp(self):
        self.fixture = fixtures.ReleasePublicInstallTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.plan = self.fixture.plan

    def installed(self, entry='actql'):
        site, _, _ = self.fixture.installed(entry)
        names = ['actql-sdk'] if entry == 'actql-sdk' else list(self.fixture.payloads)
        packages = []
        for name in names:
            info = site / (name.replace('-', '_') + '-' + self.fixture.version + '.dist-info')
            (info / 'INSTALLER').write_bytes(b'uv')
            (info / 'REQUESTED').write_bytes(b'')
            record = StringIO(); writer = csv.writer(record)
            for path in sorted(site.rglob('*')):
                if path.is_file() and (path.parent == info or path.parts[-2] == name.replace('-', '_')):
                    writer.writerow([path.relative_to(site).as_posix(), '', ''])
            (info / 'RECORD').write_text(record.getvalue())
            item = next(value for value in self.plan['artifacts'] if value['name'] == name)
            packages.append({'name': name, 'version': item['version'], 'source': {'registry': 'https://pypi.org/simple'},
                'wheels': [{'url': 'https://files.pythonhosted.org/packages/inert/' + Path(item['path']).name,
                    'hash': 'sha256:' + item['sha256'], 'size': item['bytes'], 'upload-time': '2026-01-01T00:00:00Z'}]})
        packages.append({'name': 'release-consumer-check', 'version': '0.0.0', 'source': {'virtual': '.'},
            'dependencies': [{'name': entry}],
            'metadata': {'requires-dist': [{'name': entry, 'specifier': '==' + self.fixture.version}]}})
        minor = str(sys.version_info.major) + '.' + str(sys.version_info.minor)
        lock = {'version': 1, 'revision': 3, 'requires-python': '==' + minor + '.*', 'package': packages}
        project = {'project': {'name': 'release-consumer-check', 'version': '0.0.0',
            'requires-python': lock['requires-python'], 'dependencies': [entry + '==' + self.fixture.version]}}
        lock_path = site.parent / (site.name + '-uv.lock')
        project_path = site.parent / (site.name + '-pyproject.toml')
        self.save(lock_path, lock); self.save(project_path, project)
        return site, lock_path, project_path, lock, project

    def save(self, path, body):
        path.write_text('\n'.join(key + ' = ' + toml_value(value) for key, value in body.items()) + '\n')

    def audit(self, site, lock, project, entry='actql'):
        return verify_installed_release(self.plan, lock, entry, site, manager='uv', project_path=project)

    def test_exact_sdk_and_product_use_resolution_evidence_and_full_original_payload_reader(self):
        for entry in ('actql-sdk', 'actql'):
            site, lock, project, _, _ = self.installed(entry)
            before = (lock.read_bytes(), project.read_bytes())
            value = self.audit(site, lock, project, entry)
            self.assertEqual(value['manager'], 'uv')
            self.assertEqual(value['evidenceKind'], 'uv-resolution-lock')
            self.assertNotIn('reportSha256', value)
            self.assertEqual(len(value['payloads']), 1 if entry == 'actql-sdk' else 3)
            self.assertEqual((lock.read_bytes(), project.read_bytes()), before)
            self.assertNotIn('actql_local_runtime', sys.modules)

    def test_foreign_registry_direct_local_missing_duplicate_or_alternate_actql_resolution_refuses(self):
        for change in ('registry', 'direct', 'missing', 'duplicate', 'alternate', 'source-dist', 'revision', 'fork'):
            with self.subTest(change=change):
                site, lock_path, project, lock, _ = self.installed()
                package = lock['package'][0]
                if change == 'registry': package['source']['registry'] = 'https://other.invalid/simple'
                elif change == 'direct': package['source'] = {'url': package['wheels'][0]['url']}
                elif change == 'missing': lock['package'].pop(0)
                elif change == 'duplicate': lock['package'].append(copy.deepcopy(package))
                elif change == 'alternate': package['wheels'].append(copy.deepcopy(package['wheels'][0]))
                elif change == 'source-dist': package['sdist'] = {'url': 'https://files.pythonhosted.org/a.tar.gz'}
                elif change == 'revision': lock['revision'] = 4
                else: lock['resolution-markers'] = ['sys_platform == "other"']
                self.save(lock_path, lock)
                with self.assertRaises(ValueError): self.audit(site, lock_path, project)

    def test_exact_original_wheel_filename_version_size_hash_and_public_origin_are_required(self):
        for change in ('filename', 'version', 'size', 'hash', 'local', 'credentials', 'query'):
            with self.subTest(change=change):
                site, lock_path, project, lock, _ = self.installed()
                package = lock['package'][0]; wheel = package['wheels'][0]
                if change == 'version': package['version'] = '0.0.8'
                elif change == 'size': wheel['size'] += 1
                elif change == 'hash': wheel['hash'] = 'sha256:' + 'b' * 64
                elif change == 'filename': wheel['url'] = 'https://files.pythonhosted.org/wrong.whl'
                elif change == 'local': wheel['url'] = 'file:///old/wheel.whl'
                elif change == 'credentials': wheel['url'] = wheel['url'].replace('https://', 'https://user:secret@')
                else: wheel['url'] += '?token=secret'
                self.save(lock_path, lock)
                with self.assertRaises(ValueError): self.audit(site, lock_path, project)

    def test_project_requires_one_original_public_entry_and_matching_lock_root(self):
        for change in ('extra', 'unbounded', 'sources', 'workspace', 'root', 'metadata', 'index'):
            with self.subTest(change=change):
                site, lock_path, project_path, lock, project = self.installed()
                if change == 'extra': project['project']['dependencies'].append('actql-sdk==' + self.fixture.version)
                elif change == 'unbounded': project['project']['dependencies'] = ['actql']
                elif change == 'sources': project['tool'] = {'uv': {'sources': {'actql': {'path': '/old'}}}}
                elif change == 'workspace': project['tool'] = {'uv': {'workspace': {'members': ['../*']}}}
                elif change == 'root': lock['package'][-1]['source'] = {'editable': '.'}
                elif change == 'index': project['tool'] = {'uv': {'index': [{'url': 'https://private.invalid', 'default': True}]}}
                else: lock['package'][-1]['metadata']['requires-dist'] = []
                self.save(lock_path, lock); self.save(project_path, project)
                with self.assertRaises(ValueError): self.audit(site, lock_path, project_path)

    def test_uv_persisted_exact_official_index_is_resolution_data_not_an_extra_source(self):
        site, lock, project_path, _, project = self.installed()
        project['tool'] = {'uv': {'index': [{'url': 'https://pypi.org/simple', 'default': True}]}}
        self.save(project_path, project)
        self.assertEqual(len(self.audit(site, lock, project_path)['payloads']), 3)

    def test_uv_still_checks_actual_installer_requested_record_payload_mode_and_namespace(self):
        for change in ('installer', 'requested', 'record', 'payload', 'mode', 'surplus', 'linked', 'cache'):
            with self.subTest(change=change):
                site, lock, project, _, _ = self.installed()
                info = site / ('actql_sdk-' + self.fixture.version + '.dist-info')
                if change == 'installer': (info / 'INSTALLER').write_bytes(b'pip\n')
                elif change == 'requested': (info / 'REQUESTED').unlink()
                elif change == 'record': (info / 'RECORD').write_text('')
                elif change == 'payload': (site / 'actql_sdk/__init__.py').write_bytes(b'changed')
                elif change == 'mode': (site / 'actql_sdk/__init__.py').chmod(0o600)
                elif change == 'surplus': (site / 'actql_foreign').mkdir()
                elif change == 'cache': (info / 'uv_cache.json').write_text('{"timestamp":0}')
                else:
                    path = site / 'actql_sdk/__init__.py'; target = site.parent / (site.name + '-original.py')
                    target.write_bytes(path.read_bytes()); path.unlink(); path.symlink_to(target)
                with self.assertRaises((ValueError, OSError)): self.audit(site, lock, project)

    def test_changed_project_or_lock_during_full_payload_audit_is_not_accepted(self):
        import os
        for kind in ('project', 'lock'):
            site, lock, project, _, _ = self.installed()
            selected = project if kind == 'project' else lock
            original_open = os.open
            count = 0
            def opening(path, *args, **kwargs):
                nonlocal count
                if Path(path) == selected:
                    count += 1
                    if count == 2:
                        selected.write_bytes(selected.read_bytes() + b'\n')
                return original_open(path, *args, **kwargs)
            with patch('os.open', opening), self.assertRaises(ValueError):
                self.audit(site, lock, project)
