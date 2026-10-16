import base64
import csv
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
import zipfile
from python_interface_inventory import python_interface, wheel_interfaces, source_projects


class InterfaceInventoryTests(unittest.TestCase):
    def wheel(self, files, corrupt=False):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'fixture.whl'
        record = 'owner-0.1.dist-info/RECORD'
        output = io.StringIO()
        writer = csv.writer(output)
        for name, body in files.items():
            digest = base64.urlsafe_b64encode(hashlib.sha256(body).digest()).decode().rstrip('=')
            writer.writerow([name, 'sha256=' + ('bad' if corrupt else digest), len(body)])
        writer.writerow([record, '', ''])
        with zipfile.ZipFile(path, 'w') as wheel:
            for name, body in files.items():
                wheel.writestr(name, body)
            wheel.writestr(record, output.getvalue())
        return path

    def test_wheel_record_includes_outside_directory_python_helper(self):
        result = wheel_interfaces(self.wheel({'owner/__init__.py': b'from extra.policy import decide\n',
                                             'extra/policy.py': b'def decide(value):\n    return value\n'}))
        self.assertEqual([module['module'] for module in result['modules']],
                         ['extra/policy.py', 'owner/__init__.py'])
        self.assertEqual(result['modules'][0]['operations'][0]['name'], 'decide')

    def test_private_helper_is_inventoried_inside_classified_module(self):
        previous = python_interface('def read():\n    pass\n')
        changed = python_interface('def _decide_unknown():\n    return True\ndef read():\n    return _decide_unknown()\n')
        self.assertNotEqual(previous['operations'], changed['operations'])
        self.assertEqual(changed['operations'][0]['name'], '_decide_unknown')

    def test_imported_public_binding_changes_are_exports(self):
        before = python_interface('from ._owner import A\n')
        after = python_interface('from ._owner import A, B\n')
        self.assertEqual(before['exports'], ['A'])
        self.assertEqual(after['exports'], ['A', 'B'])

    def test_old_or_modified_wheel_bytes_fail_record_verification(self):
        with self.assertRaisesRegex(ValueError, 'Wheel original digest mismatch'):
            wheel_interfaces(self.wheel({'owner/__init__.py': b''}, corrupt=True))

    def test_unknown_dynamic_export_requires_owner_projection(self):
        with self.assertRaisesRegex(ValueError, 'requires owner projection'):
            python_interface('__all__ = choose_exports()\n')

    def test_new_python_project_outside_conventional_package_directory_is_discovered(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'outside/src/new_sdk').mkdir(parents=True)
            (root / 'outside/pyproject.toml').write_text(
                '[project]\nname="new-sdk"\n[tool.setuptools.packages.find]\nwhere=["src"]\n')
            (root / 'outside/src/new_sdk/__init__.py').write_text('def decide(value):\n    return value\n')
            result = source_projects(root, ['outside/pyproject.toml', 'outside/src/new_sdk/__init__.py'])
            self.assertEqual(result['roots'][0]['name'], 'new-sdk')
            self.assertEqual(result['modules'][0]['operations'][0]['name'], 'decide')

    def test_current_three_python_projects_are_actual_source_roots(self):
        result = source_projects(Path(__file__).resolve().parent.parent)
        self.assertEqual({value['name'] for value in result['roots']}, {'actql', 'actql-sdk', 'actql-local-runtime'})
        self.assertTrue(any(value['module'].endswith('/_wire.py') for value in result['modules']))


if __name__ == '__main__':
    unittest.main()
