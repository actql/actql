"""Source-only privacy and bounds controls; no compiler or real crash reports."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest

SPEC = importlib.util.spec_from_file_location('native_compiler_diagnostics',
    Path(__file__).with_name('native-compiler-diagnostics.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CompilerDiagnosticControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='actql-diagnostic-controls-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.context = {'source': '1' * 40, 'started_ns': time.time_ns() - 1_000_000_000,
                        'tools': {'moon': '/original/bin/moon', 'moonc': '/original/bin/moonc'}}
        self.body = {'procName': 'moon', 'procPath': '/original/bin/moon',
            'exception': {'type': 'EXC_BREAKPOINT', 'signal': 'SIGTRAP',
                          'rawCodes': [1, 2], 'memory': 'PRIVATE_MEMORY',
                          'subtype': 'PRIVATE_MESSAGE'},
            'termination': {'namespace': 'SIGNAL', 'code': 5, 'environment': 'PRIVATE_ENV',
                            'indicator': 'PRIVATE_MESSAGE'},
            'environment': 'PRIVATE_ENV', 'registers': 'PRIVATE_REGISTERS',
            'faultingThread': 0,
            'threads': [{'frames': [{'symbol': 'observed_function', 'imageIndex': 0,
                                    'imageOffset': 16, 'memory': 'PRIVATE_MEMORY'}],
                         'threadState': 'PRIVATE_REGISTERS'},
                        {'frames': [{'symbol': 'UNRELATED_THREAD'}]}],
            'usedImages': [{'path': '/private/synthetic/libobserved.dylib',
                            'other': 'PRIVATE_IMAGE_PAYLOAD'}]}

    def test_only_allowed_cause_and_faulting_frames_leave_boundary(self):
        raw = json.dumps({'header': 'PRIVATE_HEADER'}) + '\n' + json.dumps(self.body)
        result = MODULE.summarize(raw.encode(), self.context['tools'])
        self.assertEqual(result['exception'], {'type': 'EXC_BREAKPOINT',
                                             'signal': 'SIGTRAP', 'rawCodes': [1, 2]})
        self.assertEqual(result['termination'], {'namespace': 'SIGNAL', 'code': 5})
        self.assertEqual(result['faulting_frames'], [{'symbol': 'observed_function',
            'imageIndex': 0, 'imageOffset': 16, 'image': 'libobserved.dylib'}])
        self.assertNotIn('PRIVATE_', json.dumps(result))
        self.assertNotIn('UNRELATED_THREAD', json.dumps(result))
        self.assertNotIn('/private/', json.dumps(result))

    def test_a_different_actual_tool_cannot_be_associated_by_name(self):
        self.body['procPath'] = '/foreign/bin/moon'
        self.assertIsNone(MODULE.summarize(json.dumps(self.body).encode(), self.context['tools']))

    def test_old_symlink_foreign_and_oversize_reports_are_not_retained(self):
        def write(name, body):
            p = self.root / name
            p.write_text(json.dumps(body))
            return p
        write('moon-new.ips', self.body)
        old = write('moon-old.ips', self.body)
        os.utime(old, ns=(0, 0))
        external = self.root / 'external'
        external.write_text('PRIVATE_EXTERNAL_PAYLOAD')
        (self.root / 'moon-link.ips').symlink_to(external)
        foreign = dict(self.body, procPath='/foreign/bin/moon')
        write('moon-foreign.ips', foreign)
        with (self.root / 'moon-oversize.ips').open('wb') as f:
            f.truncate(MODULE.MAX_REPORT_BYTES + 1)
        result = MODULE.collect(self.root, self.context)
        self.assertEqual(len(result['reports']), 1)
        self.assertFalse(result['complete'])
        self.assertIn('report-byte-bound', result['refused'])
        self.assertNotIn('PRIVATE_', json.dumps(result))

    def test_report_and_frame_bounds_do_not_become_unbounded_capture(self):
        self.body['threads'][0]['frames'] *= 40
        for i in range(MODULE.MAX_REPORTS + 1):
            (self.root / f'moon-{i}.ips').write_text(json.dumps(self.body))
        result = MODULE.collect(self.root, self.context)
        self.assertEqual(len(result['reports']), MODULE.MAX_REPORTS)
        self.assertFalse(result['complete'])
        self.assertIn('report-count-bound', result['refused'])
        self.assertTrue(all(len(x['faulting_frames']) == 32 for x in result['reports']))


if __name__ == '__main__':
    unittest.main()
