import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {runtimeField, runtimeIsError} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

// Exercise the actual result boundary with an explicit typed-classifier port.
// The real Core discrimination is tested in its package; normal use requires
// the matching installed Common, not this representation fixture.
const source = readFileSync(new URL('./effect-run-apply.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const names = ['checkedPreflight', 'effectApplyPreflightFailureObservation', 'isEffectApplyPreflightRejection'];
const bodies = names.map(name => {
  const node = tree.body.map(value => value.declaration ?? value).find(value => value.id?.name === name);
  assert(node); return source.slice(node.start, node.end);
}).join('\n');
const fixture = () => compileFunction(`const preflightRejections=new WeakSet();
  const preflightFailureObservations=new WeakMap();${bodies}
  return {check:checkedPreflight,read:effectApplyPreflightFailureObservation,branded:isEffectApplyPreflightRejection};`,
['runtimeField', 'runtimeIsError', 'checked'])(runtimeField, runtimeIsError, checked);

test('preflight observer classifies the same returned cause once without another check or current read', () => {
  const f = fixture(), cause = {}, calls = [];
  const moon = new Proxy({}, {get(_target, name) {
    assert.equal(name, 'clientProgramEffectApplyPreflightTargetVersionChanged');
    return value => {assert.strictEqual(value, cause); calls.push(value); return true;};
  }});
  let original;
  assert.throws(() => f.check({$tag: 0, _0: cause}, moon), error => {
    original = error; assert.strictEqual(error.cause, cause); assert.equal(error.code, 'MoonBitHostFailure'); return true;
  });
  assert.deepEqual(calls, [cause]); assert(f.branded(original));
  assert.deepEqual(f.read(original), {code: 'EffectTargetVersionMismatch', kind: 'target_version_mismatch', phase: 'effect_apply_preflight'});
  assert(Object.isFrozen(f.read(original)));
  assert.equal(f.read({...original}), undefined); assert.equal(f.read(new Error('Same text')), undefined);
  assert.equal(f.read(original), f.read(original)); assert.equal(calls.length, 1);
});

test('unknown or unavailable preflight classification preserves the same original primary without a version label', () => {
  for (const classify of [undefined, () => false, () => 'true', () => {throw new Error('Diagnostic only');}]) {
    const f = fixture(), cause = {};
    assert.throws(() => f.check({$tag: 0, _0: cause}, {clientProgramEffectApplyPreflightTargetVersionChanged: classify}), error => {
      assert.strictEqual(error.cause, cause); assert.equal(error.code, 'MoonBitHostFailure');
      assert(f.branded(error)); assert.equal(f.read(error), undefined); return true;
    });
  }
});

test('successful preflight result does not consult the diagnostic port or alter its returned value', () => {
  const f = fixture(), value = {};
  const moon = new Proxy({}, {get() {assert.fail('A successful check has no failed cause to classify');}});
  assert.strictEqual(f.check({$tag: 1, _0: value}, moon), value);
});
