import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createClientDispatchSourceAcquisition} from './client-dispatch-source-acquisition.mjs';

type Ref = Readonly<{runDefinitionCid: string}>;
type Ports = Parameters<typeof createClientDispatchSourceAcquisition<Ref>>[0];
type Acquisition = ReturnType<typeof createClientDispatchSourceAcquisition<Ref>>;
type Entry = Parameters<Acquisition>[0];
type Open = NonNullable<NonNullable<Ports['sourceProfile']>['sources']>[number]['open'];

const runtime = process.env.ACTQL_TEST_COMMON_RUNTIME;
const moon: object = await import(runtime === undefined ? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href
  : pathToFileURL(runtime).href);

const preparedSource = Object.freeze({checkedSource: Object.freeze({sourceRef: 'source'})});

function sourceAcquisition(open: Open, control: Ports['control']) {
  const acquire = createClientDispatchSourceAcquisition<Ref>({
    sourceProfile: {admitsSource: ref => ref === preparedSource.checkedSource.sourceRef, open},
    now: () => 'time',
    step() {},
    registry: {}, values: {}, fragment: {}, ordered: {},
    store: {}, journal: {}, retainedRelationOutput: false,
    authorityScopeCid: 'authority', control,
  });
  const entry: Entry = {ref: {runDefinitionCid: 'original-run'}, abort: new AbortController()};
  return {entry, acquire};
}

test('live Source dispatch awaits original preparation and transfers the same capture once without wire fallback', async () => {
  const prepared = {}, sourceAccess = {}, original = {}, events: string[] = [];
  const nominal = {name: 'source_evidence', identity: 'original-source', wire: '{}'};

  const control = runtimeCore({
    ...moon,
    strategyRunEvidenceName(value: unknown) {
      assert.equal(value, original);
      events.push('project');
      return nominal.name;
    },
    strategyRunEvidenceIdentity(value: unknown) {
      assert.equal(value, original);
      return nominal.identity;
    },
    strategyRunEvidenceJson(value: unknown) {
      assert.equal(value, original);
      return nominal.wire;
    },
  }).publicationControl;

  let available = false;
  const capture = Object.freeze({takeSourceEvidenceOriginal() {
    assert.equal(this, capture);
    assert.equal(available, true);
    available = false;
    events.push('take');
    return original;
  }});
  const captured = {
    capture,
    checkedSource: {sourceDataPolicyCid: 'policy'},
    async prepareSourceEvidenceOriginal(options: unknown) {
      assert.equal(this, captured);
      assert.deepEqual(options, {authorityScopeCid: 'authority', effectiveDataPolicyCid: 'policy'});
      await Promise.resolve();
      events.push('prepared');
      available = true;
    },
    issueSourceEvidence() {assert.fail('live Source converted to wire');},
    close() {assert.fail('acquisition must transfer the original capture without closing it');},
  };

  const {entry, acquire} = sourceAcquisition(async input => {
    assert.equal(input.preparedProgram, prepared);
    assert.equal(input.sourceAccess, sourceAccess);
    events.push('open');
    return captured;
  }, control);
  const result = await acquire(entry, prepared, preparedSource, sourceAccess, {originalEvidence: true});
  assert.deepEqual(result.sourceEvidence, nominal);
  assert.equal(result.sourceEvidenceWire, undefined);
  assert.equal(entry.sourceCapture, captured);
  assert.equal(available, false);
  assert.deepEqual(events, ['open', 'prepared', 'take', 'project']);
  await assert.rejects(acquire(entry, prepared, preparedSource, sourceAccess, {originalEvidence: true}),
    /ClientSourceCaptureAlreadyRetained/);
});

test('Source original transfer refuses missing or accessor ports without invoking a wire issuer', () => {
  const control = runtimeCore({
    ...moon,
    strategyRunEvidenceName: (value: {name: string}) => value.name,
    strategyRunEvidenceIdentity: () => 'foreign-evidence',
    strategyRunEvidenceJson: () => '{}',
  }).publicationControl;
  let getters = 0;
  const accessor = {get takeSourceEvidenceOriginal() {getters++; return () => ({});}};
  const inherited: unknown = Object.create({takeSourceEvidenceOriginal() {assert.fail('inherited port');}});
  for (const capture of [{}, accessor, inherited]) {
    assert.throws(() => control.takeSourceEvidenceOriginal(capture), /InstalledSourceEvidenceUnavailable/);
  }
  assert.equal(getters, 0);
  assert.throws(() => control.takeSourceEvidenceOriginal({
    takeSourceEvidenceOriginal() {return {name: 'logical_input'};},
  }), /InvalidInstalledSourceEvidence/);
});

test('Source evidence preparation failure preserves the exact capture cleanup owner and original error', async () => {
  for (const issue of [new Error('original current failed'), undefined]) {
    const captured = {
      capture: {},
      checkedSource: {sourceDataPolicyCid: 'policy'},
      async prepareSourceEvidenceOriginal() {throw issue;},
      issueSourceEvidence() {assert.fail('failed original selected wire fallback');},
      close() {assert.fail('failed capture remains with the retained cleanup owner');},
    };
    const {entry, acquire} = sourceAcquisition(async () => captured, {
      takeSourceEvidenceOriginal() {assert.fail('preparation did not finish');},
    });
    let failed = false;
    try {
      await acquire(entry, {}, preparedSource, {}, {originalEvidence: true});
    } catch (actual) {
      failed = true;
      assert.equal(actual, issue);
    }
    assert.equal(failed, true);
    assert.equal(entry.sourceCapture, captured);
    assert.equal(entry.physicalWorkMayHaveStarted, true);
  }
});
