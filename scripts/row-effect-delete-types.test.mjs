// Actual public declarations and the existing typed consumer. These checks
// compile only: they issue no Site, runtime handle, request or cleanup ACK.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import ts from 'typescript';

const sourcePath = fileURLToPath(new URL('../packages/local-node/connector-installation.typecheck.mts', import.meta.url));
const source = readFileSync(sourcePath, 'utf8');
const options = {strict: true, noEmit: true, types: [],
  target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.NodeNext,
  moduleResolution: ts.ModuleResolutionKind.NodeNext};
function check(text) {
  const host = ts.createCompilerHost(options), read = host.readFile;
  host.readFile = path => path === sourcePath ? text : read(path);
  const program = ts.createProgram([sourcePath], options, host);
  return ts.getPreEmitDiagnostics(program).map(diagnostic => ({
    code: diagnostic.code,
    file: diagnostic.file?.fileName,
    line: diagnostic.file?.getLineAndCharacterOfPosition(diagnostic.start ?? 0).line,
    message: ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'),
  }));
}

test('public DELETE, original value-bearing and Command consumers typecheck without casts or dummy values', () => {
  assert.deepEqual(check(source), []);
});

test('public types actually reject proposed DELETE values and missing original value or cleanup', () => {
  const expected = [];
  const mutant = source.split('\n').map((line, index) => {
    if (!line.includes('// @ts-expect-error DELETE:') &&
        !line.includes('// @ts-expect-error Value-bearing:')) return line;
    expected.push(index + 1);
    return line.replace('@ts-expect-error', 'Independent expected diagnostic');
  }).join('\n');
  assert.equal(expected.length, 8);
  const diagnostics = check(mutant);
  assert.equal(diagnostics.length, expected.length, JSON.stringify(diagnostics));
  assert(diagnostics.every(row => row.file === sourcePath), JSON.stringify(diagnostics));
  assert.deepEqual(diagnostics.map(row => [row.line, row.code]),
    expected.map((line, index) => [line, [2322, 2322, 2322, 2322, 2322, 2322, 2741, 2741][index]]));
});
