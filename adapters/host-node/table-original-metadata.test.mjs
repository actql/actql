import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const catalog = fileURLToPath(new URL('../connectors/local/iceberg/catalog.py', import.meta.url));
// Execute the actual method AST without importing optional Arrow/Iceberg or
// constructing a Catalog/SQLite owner. The fixtures own only fresh byte files.
const original = String.raw`
import ast, hashlib, tempfile
from pathlib import Path
from types import SimpleNamespace

source = Path(__import__('sys').argv[1])
tree = ast.parse(source.read_text())
owner = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == 'TableCatalog')
method = next(node for node in owner.body if isinstance(node, ast.FunctionDef) and node.name == 'generation')
namespace = {'hashlib': hashlib}
exec(compile(ast.Module(body=[method], type_ignores=[]), str(source), 'exec'), namespace)
generation = namespace['generation']
`;

function run(body) {
  const result = spawnSync(process.env.ACTQL_TABLE_PYTHON ?? 'python3',
    ['-I', '-B', '-c', original + body, catalog],
    {encoding: 'utf8', timeout: 10000, maxBuffer: 65536});
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
}

test('Table original metadata generation hashes all exact bytes with one bounded reusable scratch', () => {
  run(String.raw`
with tempfile.TemporaryDirectory(prefix='actql-table-hash-only-') as directory:
    path = Path(directory) / 'original.metadata.json'
    payload = bytes(range(256)) * 1024 + b'\x00\xff'
    path.write_bytes(payload)
    opened, closed, whole_reads, sizes, buffers = [], [], [], [], []
    class Stream:
        def __init__(self): self.raw = path.open('rb', buffering=0)
        def __enter__(self): return self
        def __exit__(self, *_): self.raw.close(); closed.append(True)
        def readinto(self, target):
            sizes.append(len(target)); buffers.append(id(target.obj) if isinstance(target, memoryview) else id(target))
            assert len(target) <= 65536, 'metadata-sized hash scratch'
            return self.raw.readinto(target)
    class OriginalPath:
        def read_bytes(self): whole_reads.append(True); return path.read_bytes()
        def open(self, mode, *, buffering):
            assert mode == 'rb' and buffering == 0
            opened.append(True); return Stream()
    selected = OriginalPath()
    calls = []
    def local_path(location):
        assert location == 'same-original-location'; calls.append(location); return selected
    value = generation(SimpleNamespace(local_path=local_path), 'same-original-location')
    assert value == 'sha256:' + hashlib.sha256(payload).hexdigest()
    assert whole_reads == [], 'generation allocated the complete original metadata'
    assert len(opened) == len(closed) == len(calls) == 1
    assert len(sizes) >= 5 and len(set(buffers)) == 1
    path.write_bytes(b'')
    assert generation(SimpleNamespace(local_path=local_path), 'same-original-location') == 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
`);
});

test('Table original metadata read failure closes the same FD without retry or a partial generation', () => {
  run(String.raw`
with tempfile.TemporaryDirectory(prefix='actql-table-hash-failure-only-') as directory:
    path = Path(directory) / 'original.metadata.json'
    path.write_bytes(b'original metadata bytes')
    cause = OSError('original-read-failure')
    opened, closed, reads = [], [], []
    class Stream:
        def __init__(self): self.raw = path.open('rb', buffering=0)
        def __enter__(self): return self
        def __exit__(self, *_): self.raw.close(); closed.append(True)
        def readinto(self, target):
            reads.append(True)
            if len(reads) == 2: raise cause
            return self.raw.readinto(memoryview(target)[:7])
    class OriginalPath:
        def read_bytes(self): return path.read_bytes()
        def open(self, mode, *, buffering):
            assert mode == 'rb' and buffering == 0
            opened.append(True); return Stream()
    try:
        generation(SimpleNamespace(local_path=lambda _: OriginalPath()), 'same-original-location')
    except OSError as observed:
        assert observed is cause
    else:
        raise AssertionError('read failure returned a generation')
    assert len(opened) == len(closed) == 1 and len(reads) == 2
`);
});
