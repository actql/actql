"""Selected interpreter/consumer orchestration guards, not wheel acceptance."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('supported_python', SCRIPTS / 'ci-supported-python.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class SupportedPythonTests(unittest.TestCase):
    def test_version_and_platform_refuse_before_allocating_a_consumer(self):
        with patch.object(ci.platform, 'python_version', return_value='3.14.5'), \
                patch.object(ci.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'exact supported Python interpreter'):
                ci.accept(Path('/no-cohort-read'), Path('/no-directory'), '3.11.0')
            run.assert_not_called()
        with patch.object(ci.platform, 'python_version', return_value='3.11.0'), \
                patch.object(ci.sys, 'platform', 'linux'), patch.object(ci.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'darwin-arm64 only'):
                ci.accept(Path('/no-cohort-read'), Path('/no-directory'), '3.11.0')
            run.assert_not_called()

    def test_same_cohort_installs_only_wheels_and_audits_before_and_after_health(self):
        with tempfile.TemporaryDirectory(prefix='actql-supported-python-guards-') as temp:
            root = Path(temp).resolve()
            cohort_directory = root / 'cohort'
            cohort_directory.mkdir()
            cohort = {'package_version': '0.0.0.dev0', 'wheels': [
                {'distribution': name, 'file': name + '.whl'}
                for name in ('actql-sdk', 'actql-local-runtime', 'actql')]}
            (cohort_directory / 'cohort.json').write_text(json.dumps(cohort))
            calls = []
            def command(args, **options):
                calls.append(([str(arg) for arg in args], options))
            def git(args, **options):
                return b'' if 'status' in args else 'a' * 40 + '\n'
            with patch.object(ci.platform, 'python_version', return_value='3.11.0'), \
                    patch.object(ci.sys, 'platform', 'darwin'), patch.object(ci.platform, 'machine', return_value='arm64'), \
                    patch.object(ci.subprocess, 'check_output', side_effect=git), \
                    patch.object(ci.subprocess, 'run', side_effect=command), \
                    patch.object(ci, 'verify_built_cohort', return_value={'cohort': cohort}) as verify:
                destination = root / 'consumer'
                ci.accept(cohort_directory, destination, '3.11.0')
            self.assertEqual(len(calls), 6)
            bootstrap = calls[1][0]
            self.assertIn('--require-hashes', bootstrap)
            self.assertIn('--only-binary=:all:', bootstrap)
            pip_requirement = (destination / 'pip-requirements.txt').read_text()
            self.assertEqual(pip_requirement, 'pip==26.3 --hash=sha256:f3b60b20ffaadd4415ed7957212a38ac63fa4c5fa375bd0f4a797777940fad13\n')
            install = calls[2][0]
            self.assertIn('--only-binary=:all:', install)
            self.assertIn('--constraint', install)
            self.assertEqual(install[-1], str(cohort_directory / 'wheels/actql.whl'))
            constraints = (destination / 'constraints.txt').read_text()
            for item in cohort['wheels']:
                self.assertIn((cohort_directory / 'wheels' / item['file']).as_uri(), constraints)
            self.assertTrue(calls[3][0][3].endswith('ci-python-installed-audit.py'))
            self.assertTrue(calls[4][0][3].endswith('ci-python-installed-run.py'))
            self.assertTrue(calls[4][0][4].endswith('ci-python-installed-health.py'))
            self.assertTrue(calls[5][0][3].endswith('ci-python-installed-audit.py'))
            self.assertEqual(verify.call_count, 2)
            for args, options in calls[1:]:
                self.assertEqual(options['cwd'], destination)
                self.assertNotIn('PYTHONPATH', options['env'])
                self.assertTrue(options['check'])
            self.assertFalse(any('build-python' in value or 'compile-python' in value for args, _ in calls for value in args))


if __name__ == '__main__':
    unittest.main()
