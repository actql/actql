import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import ts from 'typescript';
import {compilerBindingTargets, generateCompilerBindings} from './generate-js-compiler-bindings.mjs';

function fixture(t: {after(action: () => void): void}) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-typed-compiler-binding-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const root = pathToFileURL(directory + '/');
  for (const relative of ['tsconfig.base.json', 'scripts/templates/js-compiler-binding.mts']) {
    const target = join(directory, relative);
    mkdirSync(dirname(target), {recursive: true});
    writeFileSync(target, readFileSync(new URL('../' + relative, import.meta.url)));
  }
  for (const target of compilerBindingTargets) mkdirSync(dirname(join(directory, target)), {recursive: true});
  return {root, directory};
}

test('one authored compiler binding emits dependency-free runtime and conservative declarations', async t => {
  const {root, directory} = fixture(t);
  generateCompilerBindings(root, true);
  generateCompilerBindings(root);
  const binding = compilerBindingTargets[0]!;
  const originalRuntime = readFileSync(new URL(binding, root), 'utf8');
  const originalTypes = readFileSync(new URL(binding.replace(/\.mjs$/u, '.d.mts'), root), 'utf8');
  for (const path of compilerBindingTargets) {
    assert.equal(readFileSync(new URL(path, root), 'utf8'), originalRuntime);
    assert.equal(readFileSync(new URL(path.replace(/\.mjs$/u, '.d.mts'), root), 'utf8'), originalTypes);
  }
  const runtime = await import(new URL(binding, root).href) as typeof import('./templates/js-compiler-binding.mjs');
  const first = Object.freeze({original: 9007199254740993n}), second = Object.freeze({original: 'λ'});
  const pair = runtime.runtimePair(first, second);
  assert.equal(runtime.runtimeField(pair, 0), first);
  assert.equal(runtime.runtimeField(pair, 1), second);
  assert.equal(runtime.runtimeOptionalField(undefined, 0), undefined);
  assert.throws(() => runtime.runtimeField(undefined, 0), TypeError);
  assert.throws(() => runtime.runtimeIsOkRequired(null), TypeError);
  assert.equal(runtime.runtimeIsOk({$tag: 1}), true);
  for (const raw of [undefined, null, false, 1, {}, {$tag: '1'}, {$tag: 2}]) {
    assert.equal(runtime.runtimeIsOk(raw), false);
  }
  assert.equal(runtime.runtimeField(runtime.runtimeFailure(first), 0), first);
  assert.equal(runtime.runtimeUnboxedReferenceOption(first), first);
  assert.equal(runtime.runtimeUnboxedUnitOptionPresent(-1), false);
  assert.equal(runtime.runtimeUnboxedUnitOptionPresent(undefined), true);
  assert.deepEqual(runtime.runtimeTupleFromFields({0: first, 2: second}), {_0: first, _2: second});

  const consumer = join(directory, 'consumer.mts');
  writeFileSync(consumer, `import {runtimeField, runtimeIsOk, runtimePair} from './${binding}';
const original = Object.freeze({value: 7});
const pair = runtimePair(original, 'value');
const retained: typeof original = pair._0;
const raw: unknown = runtimeField(pair, 0);
// @ts-expect-error Representation access does not validate the payload.
const admitted: {value: number} = runtimeField(pair, 0);
if (runtimeIsOk(raw)) {
  // @ts-expect-error A matching discriminant is not payload admission.
  const stillUnknown: {value: number} = raw;
}
void retained;
`);
  const config = ts.readConfigFile(join(directory, 'tsconfig.base.json'), ts.sys.readFile);
  const options = ts.convertCompilerOptionsFromJson(config.config.compilerOptions, directory).options;
  const diagnostics = ts.getPreEmitDiagnostics(ts.createProgram([consumer], {...options, noEmit: true, types: []}));
  assert.deepEqual(diagnostics.map(value => ts.flattenDiagnosticMessageText(value.messageText, '\n')), []);
});

test('the existing freshness boundary refuses a stale declaration as well as stale runtime', t => {
  const {root} = fixture(t);
  generateCompilerBindings(root, true);
  const runtime = compilerBindingTargets[0]!;
  const declaration = runtime.replace(/\.mjs$/u, '.d.mts');
  for (const selected of [runtime, declaration]) {
    const target = new URL(selected, root), original = readFileSync(target, 'utf8');
    writeFileSync(target, original + '\n// stale\n');
    assert.throws(() => generateCompilerBindings(root), /Stale private compiler binding/u);
    assert.equal(readFileSync(target, 'utf8'), original + '\n// stale\n');
    writeFileSync(target, original);
  }
});

test('invalid authored source refuses before writes and ignored bootstrap emit is never an input', t => {
  const {root} = fixture(t);
  generateCompilerBindings(root, true);
  const runtime = new URL(compilerBindingTargets[0]!, root), original = readFileSync(runtime, 'utf8');
  writeFileSync(new URL('scripts/templates/js-compiler-binding.mjs', root), 'throw new Error("StaleBootstrap");');
  generateCompilerBindings(root);
  const source = new URL('scripts/templates/js-compiler-binding.mts', root);
  writeFileSync(source, readFileSync(source, 'utf8') + '\nexport const invalid = missingBinding;\n');
  assert.throws(() => generateCompilerBindings(root, true), /Cannot find name 'missingBinding'/u);
  assert.equal(readFileSync(runtime, 'utf8'), original);
});
