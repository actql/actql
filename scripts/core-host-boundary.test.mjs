import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {copyProductionCore} from './portable-core.mjs';

// Real pinned-compiler evidence: read-only projections are not constructors,
// record-update authority, mutable fields, or access to the owned arrays.
test('checked graph projections cannot forge or mutate an owned proof', {timeout: 180_000}, t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const temporary = mkdtempSync(join(tmpdir(), 'actql-checked-graph-boundary-'));
  t.after(() => rmSync(temporary, {recursive: true, force: true}));
  copyProductionCore(root, temporary);
  const probe = join(temporary, 'src', 'external_probe');
  mkdirSync(probe);
  writeFileSync(join(probe, 'moon.pkg'), `supported_targets = "+js+wasm+native"
import {
  "actql/actql/physical_strategy" @graph,
  "actql/actql/execution_relation" @execution,
  "actql/actql/lowering_relation" @lower,
}
`);
  const check = source => {
    writeFileSync(join(probe, 'probe.mbt'), source);
    const result = spawnSync('moon', ['check', '--target', 'js', 'src/external_probe'], {
      cwd: temporary, encoding: 'utf8', timeout: 120_000, maxBuffer: 8 * 1024 * 1024,
    });
    assert.equal(result.error, undefined, result.error?.message);
    assert.equal(result.signal, null, result.stderr);
    return {status: result.status, output: result.stdout + result.stderr};
  };
  const positive = check(`pub fn task(value : @graph.CheckedEffectSourcePort) -> Int { value.task }
pub fn owner(value : @graph.CheckedDAG) -> @lower.BoundPrepared? { value.owners_at(0) }
pub fn bound(value : @lower.Expression) -> @lower.ExpressionTextBound? { @lower.expression_text_bound(value) }
`);
  assert.equal(positive.status, 0, positive.output);
  const cases = [
    ['text bound construction', `pub fn forge() -> @lower.ExpressionTextBound {
      { original: 0 }
    }`, /abstract type|not a struct|Cannot create/],
    ['text bound nominal constructor', `pub fn forge(value : @lower.ExpressionTextBound) -> @lower.ExpressionTextBound {
      @lower.ExpressionTextBound(value)
    }`, /Cannot create|not found|not a constructor|not exported|not public|abstract type/i],
    ['text bound unwrap', `pub fn forge(value : @lower.ExpressionTextBound) -> Int {
      value.0
    }`, /abstract type|not a tuple|not a newtype|cannot access|wanted\s*:\s*tuple/i],
    ['text bound original escape', `pub fn forge(value : @lower.ExpressionTextBound) -> Int {
      value.original
    }`, /abstract type and not a struct/],
    ['construction', `pub fn forge(occurrence : @execution.ManagedResultOccurrence) -> @graph.CheckedEffectSourcePort {
      { member_index: 0, stage: 0, task: 0, occurrence }
    }`, /Cannot create values of the read-only type/],
    ['record update', `pub fn forge(value : @graph.CheckedEffectSourcePort) -> @graph.CheckedEffectSourcePort {
      { ..value, task: 1 }
    }`, /Cannot create values of the read-only type/],
    ['field mutation', `pub fn mutate(value : @graph.CheckedEffectSourcePort) -> Unit { value.task = 1 }`, /not mutable|immutable|read.only/i],
    ['array escape', `pub fn leak(value : @graph.CheckedDAG) -> Array[@lower.BoundPrepared] { value.owners }`, /abstract type and not a struct/],
  ];
  for (const [name, source, diagnostic] of cases) {
    const actual = check(source);
    assert.notEqual(actual.status, 0, `${name} unexpectedly compiled`);
    assert.match(actual.output, diagnostic, `${name}: ${actual.output}`);
  }
});

// Prove the pinned compiler keeps a nominal view allocation-free on every
// supported backend. This representation probe is not Host runtime acceptance.
test('text-bound nominal view adds no owned representation on JS Wasm or Native', t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const declaration = readFileSync(join(root, 'src/lowering_relation/expression_text_bound.mbt'), 'utf8');
  assert.match(declaration, /struct ExpressionTextBound\(@context\.TextBoundResolution\)/);
  const temporary = mkdtempSync(join(tmpdir(), 'actql-newtype-layout-'));
  t.after(() => rmSync(temporary, {recursive: true, force: true}));
  const source = join(temporary, 'probe.mbt');
  writeFileSync(source, `struct Original { value : Int }
struct ExpressionTextBound(Original)
pub fn wrap(value : Original) -> ExpressionTextBound { ExpressionTextBound(value) }
pub fn unwrap(value : ExpressionTextBound) -> Original { value.0 }
pub fn make(value : Int) -> Original { { value, } }
pub fn read(value : Original) -> Int { value.value }
`);
  for (const [target, suffix] of [['js', 'js'], ['wasm', 'wat'], ['native', 'c']]) {
    const output = join(temporary, `probe.${suffix}`);
    const args = ['compile', '-target', target, '-std-path', join(process.env.MOON_HOME, 'lib/core'),
      '-exported_functions', 'wrap,unwrap,make,read', '-o', output, source];
    if (target === 'native') args.splice(3, 0, '-S');
    const result = spawnSync('moonc', args, {encoding: 'utf8', timeout: 30_000});
    assert.equal(result.error, undefined, result.error?.message);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const code = readFileSync(output, 'utf8');
    // A nominal single-field tuple is erased, not another record/layout.
    assert.doesNotMatch(code, /struct _M\w*ExpressionTextBound|function _M\w*ExpressionTextBound\(/);
    for (const name of ['wrap', 'unwrap']) {
      const body = target === 'wasm'
        ? code.match(new RegExp(`\\(func \\$_M[^\\s(]*${name} [\\s\\S]*?(?=\\n\\(export)`))?.[0]
        : code.match(new RegExp(`(?:function|struct [^\\n]+\\*) _M[^\\s(]*${name}\\([^)]*\\) \\{([^}]+)\\}`))?.[0];
      assert.ok(body, `${target} ${name} implementation missing`);
      assert.doesNotMatch(body, /\bnew\b|malloc|alloc\(|struct\.new/);
      assert.match(body, target === 'wasm' ? /local\.get/ : /return/);
    }
  }
});
