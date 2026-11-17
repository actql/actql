import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from './runtime-core.mjs';
import {runtimeTupleFromFields} from './compiler-binding.generated.mjs';

const ok = value => ({$tag: 1, _0: value});
// Actual adapter with explicit nominal Core ports, not an issued Run or Source
// completion. The ordinary capture verifies genuine Core originals separately.
function fixture() {
  const definition = {name: 'run_definition', identity: 'sha256:' + '1'.repeat(64), wire: '{}'};
  const admission = {}, allowed = {}, observation = {name: 'observation_set', identity: 'observation', wire: '{}'};
  const invocation = {name: 'run_invocation', identity: 'invocation', wire: '{}'};
  const limits = {maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 100};
  const parent = {}, prepared = {}, request = {}, plan = {}, host = {}, compilation = {}, lookup = {};
  let calls = 0, refusal;
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'fixture metadata',
    clientProgramAllowedEffectRunAdmission(value) {assert.strictEqual(value, allowed); return admission;},
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'cid',
    strategyPublicationContractIdentity: value => value.identity,
    strategyPublicationContractJson: value => value.wire,
    strategyRunEvidenceName: value => value.name,
    strategyRunEvidenceIdentity: value => value.identity,
    strategyRunEvidenceJson: value => value.wire,
    clientProgramIssueInstalledEffectKeyedInvocation(...args) {
      calls++;
      assert.deepEqual(args.slice(0, 7), [parent, prepared, request, plan, host, compilation, admission]);
      assert.strictEqual(args[7], definition, 'retain the checked Plan Definition, not its JS view or an equal body');
      assert.strictEqual(args[8], lookup);
      if (refusal !== undefined) throw refusal;
      return ok(runtimeTupleFromFields([observation, invocation]));
    },
  };
  const control = runtimeCore(moon).publicationControl;
  const original = control.originalCheckedClientEffectPublication(allowed, definition, limits);
  return {definition, original, limits, calls: () => calls, refuse(value) {refusal = value;},
    issue(view = original.runDefinition) {
      return control.issueCheckedInstalledEffectKeyedInvocation(parent, prepared, request, plan, host,
        compilation, original.admission, view, lookup, 'start', 'completed', limits);
    }};
}

test('keyed invocation unwraps the same original checked Definition view and preserves the Core refusal', () => {
  const f = fixture(), issued = f.issue();
  assert.equal(issued.invocation.name, 'run_invocation'); assert.equal(f.calls(), 1);
  const failure = new Error('same original current refused'); f.refuse(failure);
  assert.throws(() => f.issue(), error => error === failure); assert.equal(f.calls(), 2);
});

test('keyed invocation refuses equal copied and foreign namespace Definition views before Core', () => {
  const f = fixture(), other = fixture();
  for (const view of [{...f.original.runDefinition}, other.original.runDefinition]) {
    assert.throws(() => f.issue(view), /Foreign publication contract/);
  }
  assert.equal(f.calls(), 0);
});
