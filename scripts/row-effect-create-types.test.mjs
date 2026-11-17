// Public declaration acceptance and independent rejection of conflicting author
// implementations. This imports no runtime and creates no execution authority.
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
    code: diagnostic.code, file: diagnostic.file?.fileName,
    line: diagnostic.file?.getLineAndCharacterOfPosition(diagnostic.start ?? 0).line,
    message: ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'),
  }));
}

test('standard CREATE and existing driver consumers use the same public exclusive factory', () => {
  assert.deepEqual(check(source), []);
});

test('standard CREATE rejects conflicting/missing implementations and invalid pure callbacks', () => {
  const scenarios = new Set(['mode-conflict', 'mode-missing', 'async-request',
    'async-classification', 'unsupported-kind', 'write-method', 'request-query', 'no-authority']);
  const locations = new Map();
  const mutant = source.split('\n').map((line, index) => {
    const marker = /@ts-expect-error Standard CREATE \[([a-z-]+)\]:/u.exec(line);
    if (!marker) return line;
    assert(scenarios.has(marker[1]), `Unreviewed rejection scenario: ${marker[1]}`);
    assert(!locations.has(marker[1]), `Duplicate rejection scenario: ${marker[1]}`);
    locations.set(marker[1], index + 1);
    return line.replace('@ts-expect-error', 'Independent expected diagnostic');
  }).join('\n');
  assert(locations.size > 0, 'No rejection scenarios discovered');
  assert.deepEqual(new Set(locations.keys()), scenarios);
  const diagnostics = check(mutant);
  assert.equal(diagnostics.length, locations.size, JSON.stringify(diagnostics));
  assert(diagnostics.every(row => row.file === sourcePath), JSON.stringify(diagnostics));
  for (const [scenario, line] of locations) {
    assert.equal(diagnostics.filter(row => row.line === line).length, 1,
      `Expected rejection of ${scenario}: ${JSON.stringify(diagnostics)}`);
  }
});
