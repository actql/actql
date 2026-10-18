"""Compiler program correspondence/refusal counters; no native code runs."""
import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import python_compiler_program as program
import test_local_image_compiler as image
from actql_sdk._local_distribution import LocalInstallationError


class CompilerProgramTests(unittest.TestCase):
    def setUp(self):
        self.case = image.ImageCompilerTests()
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.original = image.compiler.verify(self.case.case.module_file, self.case.case.head)
        self.root = self.case.case.root.resolve()
        self.headers = self.root / 'headers'
        self.headers.mkdir()
        self.header = self.headers / 'wasm.h'
        self.header.write_bytes(b'independent fixed header closure fixture')
        self.declaration = dict(scope='maintainer_compiler_c_api_headers_only',
            upstream_git_commit='a' * 40, runtime_version=program.WASMTIME_VERSION,
            target='aarch64-apple-darwin', features='independent fixture, no compilation',
            generated_configuration='independent fixture, no configuration', headers=[
                dict(path='wasm.h', bytes=self.header.stat().st_size,
                     sha256=hashlib.sha256(self.header.read_bytes()).hexdigest())])
        base = self.case.case.source / program.BASE
        base.mkdir(parents=True, exist_ok=True)
        (base / 'workspace-build-inputs.json').write_text(json.dumps(dict(
            upstream_git_commit='a' * 40, target='aarch64-apple-darwin')))
        self.declaration_path = base / 'compiler-c-api-headers.json'
        self.declaration_path.write_text(json.dumps(self.declaration))
        self.case.case.commit()
        self.source = self.case.case.head
        self.case.case.core['source_sha'] = self.source
        self.case.case.write_receipts()
        self.original = image.compiler.verify(self.case.case.module_file, self.source)
        self.patch = patch.object(program, 'ROOT', self.case.case.source)
        self.patch.start(); self.addCleanup(self.patch.stop)

    def test_header_closure_requires_exact_members_and_bytes(self):
        records = program._headers(self.source, self.headers)
        self.assertEqual(records, ((str(self.header), self.header.stat().st_size,
                                   hashlib.sha256(self.header.read_bytes()).hexdigest()),))
        self.header.write_bytes(b'changed header')
        with self.assertRaisesRegex(ValueError, 'original header closure'):
            program._headers(self.source, self.headers)

    def test_extra_precompiled_header_and_symlink_refuse(self):
        extra = self.headers / 'wasm.h.gch'
        extra.write_bytes(b'unrecorded precompiled input')
        with self.assertRaisesRegex(ValueError, 'original header closure'):
            program._headers(self.source, self.headers)
        extra.unlink(); extra.symlink_to(self.header)
        with self.assertRaisesRegex(ValueError, 'nonregular'):
            program._headers(self.source, self.headers)

    def test_foreign_or_uncommitted_header_selection_refuses(self):
        self.declaration_path.write_text(self.declaration_path.read_text() + '\n')
        with self.assertRaisesRegex(ValueError, 'committed original'):
            program._headers(self.source, self.headers)

    def prepared(self):
        executable = self.root / 'compiler-image'
        library = self.root / 'original-library'
        executable.write_bytes(b'independent executable fixture')
        library.write_bytes(b'independent actual link input fixture')
        def record(path):
            data = path.read_bytes()
            return str(path), len(data), hashlib.sha256(data).hexdigest()
        return program._CompilerProgram(self.original['source'], self.original['module_sha256'],
            self.original['core_receipt_sha256'], hashlib.sha256(self.original['recipe'].engine_body).hexdigest(),
            self.root, record(executable), (record(library),))

    def test_module_source_receipt_and_configuration_are_separate_exact_bindings(self):
        prepared = self.prepared()
        self.assertEqual(program.verify_program(self.original, prepared), Path(prepared.executable[0]))
        for field in ('source', 'module_sha256', 'receipt_sha256', 'engine_sha256'):
            with self.subTest(field=field):
                with self.assertRaisesRegex(ValueError, 'another original module/recipe'):
                    program.verify_program(self.original, prepared._replace(**{field:'f' * 64}))

    def test_changed_executable_or_actual_link_input_refuses(self):
        prepared = self.prepared()
        library = Path(prepared.inputs[0][0])
        original = library.read_bytes()
        library.write_bytes(b'changed')
        with self.assertRaises(LocalInstallationError):
            program.verify_program(self.original, prepared)
        library.write_bytes(original)
        Path(prepared.executable[0]).write_bytes(b'changed')
        with self.assertRaises(LocalInstallationError):
            program.verify_program(self.original, prepared)

    def test_invalid_preparation_budget_refuses_before_source_or_compiler(self):
        for seconds in (True, 0, float('inf')):
            with self.subTest(seconds=seconds), patch.object(program.subprocess, 'run',
                    side_effect=AssertionError('Compiler')):
                with self.assertRaisesRegex(ValueError, 'original compiler inputs'):
                    program.prepare_program(self.original, headers=self.headers,
                        clang=self.root / 'clang', sdk=self.root, destination=self.root / 'new-program', seconds=seconds)

    def test_ordinary_producer_requires_original_tools_before_runtime_preparation(self):
        with patch.object(image.compiler, 'prepare_compiler_runtime', side_effect=AssertionError('Stage')):
            with self.assertRaisesRegex(ValueError, 'binding/library/header/toolchain'):
                image.compiler.prepare_compiler_executable(self.case.case.module_file, self.case.case.head,
                    self.root / 'new-program', bindings_source=None, native_libraries=None, preparation=None,
                    c_api_headers=None, clang=None, sdk=None, seconds=50)


if __name__ == '__main__':
    unittest.main()
