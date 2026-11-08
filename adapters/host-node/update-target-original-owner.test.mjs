import assert from 'node:assert/strict';
import {readFile, mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
const moon = await import(process.env.ACTQL_TEST_UPDATE_ORIGINAL_RUNTIME === undefined
  ? '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'
  : pathToFileURL(process.env.ACTQL_TEST_UPDATE_ORIGINAL_RUNTIME).href);
import {encodeUpdateTargetData, encodeUpdateTargetOriginalData} from './update-target-data.generated.mjs';
import {updateTargetSelectionsCid, updateTargetOriginalDataEqual,
  issueUpdateTargetInstallation, installationsShape,
  updateTargetPreparedOriginalShape} from './update-target-original-shape.mjs';
import {generateUpdateTargetDataCodec} from '../../scripts/generate-update-target-data-codec.mjs';

test('actual selection DATA reader retains every independent original identity vector', async () => {
  const corpus = JSON.parse(await readFile(new URL('../../portability/corpus/effect-target-selection.json', import.meta.url)));
  assert.ok(corpus.cases.length >= 9);
  for (const entry of corpus.cases) {
    assert.equal(updateTargetSelectionsCid(entry.preimage, moon), entry.expected_cid, entry.id);
  }
  const original = corpus.cases[0].preimage;
  for (const invalid of [[], null, [{...original[0], extra: true}],
    [{...original[0], stage_index: -1}], [{...original[0], effect_id: ''}],
    [{...original[0], effect_id: '\ud800'}]]) {
    assert.throws(() => updateTargetSelectionsCid(invalid, moon));
  }
});

test('transport conversion preserves public DATA names without interpreting compiler representation', () => {
  const original = {['__proto__']: 'data', $tag: 1, _0: 'e\u0301\r\n', _1: {value: null}};
  assert.deepEqual(JSON.parse(encodeUpdateTargetData(original)), original);
  assert.equal(updateTargetOriginalDataEqual(moon, original, structuredClone(original)), true);
  assert.equal(updateTargetOriginalDataEqual(moon, original, {...original, _0: 'é\n'}), false);
});

test('transport snapshot reads each original field and array length once', () => {
  let reads = 0, lengths = 0;
  const object = {get value() { reads++; return reads === 1 ? 'original' : 'changed'; }};
  assert.equal(encodeUpdateTargetData(object), '{"value":"original"}');
  assert.equal(reads, 1);
  const array = new Proxy(['original'], {get(target, key, receiver) {
    if (key === 'length') lengths++;
    return Reflect.get(target, key, receiver);
  }});
  assert.equal(encodeUpdateTargetData(array), '["original"]');
  assert.equal(lengths, 1);
});

test('complete material envelope keeps the independent metadata and inner-material limits', () => {
  const profile = {continuation: 'actql-installed-row-effect-continuation/0.1',
    continuationBinding: 'binding_cid', dispatch: 'actql-installed-row-effect-dispatch/0.1',
    recovery: 'actql-installed-row-effect-recovery/0.1', source: 'actql-installed-row-effect-source/0.1',
    targetCheck: 'actql-installed-row-effect-check/0.1', unit: 'actql-installed-row-effect-unit/0.1'};
  const installation = issueUpdateTargetInstallation(moon, {binding_cid: 'sha256:' + 'c'.repeat(64),
    connection: 'fixture', connector_registration: 'update_target_fixture',
    connector_revision: 'update_target_fixture/0.1', continuation_binding: 'sha256:' + 'e'.repeat(64),
    profile, runtime_bundle_cid: 'sha256:' + 'd'.repeat(64)});
  const original = {preparedWire: '"'.repeat(60000), compiledPlanCid: 'sha256:' + 'a'.repeat(64),
    installations: [installation]};
  assert.throws(() => encodeUpdateTargetData(original), /InvalidUpdateTargetData/u);
  assert(Buffer.byteLength(encodeUpdateTargetOriginalData(original)) > 65536);
  assert.equal(updateTargetPreparedOriginalShape(original, moon), true);
  assert.equal(updateTargetOriginalDataEqual(moon, original, structuredClone(original)), true);
  assert.equal(updateTargetPreparedOriginalShape({...original, preparedWire: 'a'.repeat(262145)}, moon), false);
  assert.equal(updateTargetPreparedOriginalShape({...original, installations: [
    {...installation, wire: 'a'.repeat(65536)}]}, moon), false);
});

test('transport bounds reject limit plus one cycles invalid text and non-JSON values before encoding', () => {
  assert.deepEqual(moon.clientProgramEffectTargetOriginalCodecLimits(), [65536, 65536, 64]);
  assert.equal(Buffer.byteLength(encodeUpdateTargetData('a'.repeat(65534))), 65536);
  const cycle = {}; cycle.self = cycle;
  let depth = null;
  for (let index = 0; index < 64; index++) depth = [depth];
  for (const invalid of ['a'.repeat(65535), '\\'.repeat(32768), '\ud800',
    {value: undefined}, 1n, -0, Infinity, cycle, depth]) {
    assert.throws(() => encodeUpdateTargetData(invalid), {message: 'InvalidUpdateTargetData'});
  }
});

test('actual installation Owner refuses changed saved data rather than authenticating a caller CID', () => {
  const profile = {continuation: 'actql-installed-row-effect-continuation/0.1',
    continuationBinding: 'binding_cid', dispatch: 'actql-installed-row-effect-dispatch/0.1',
    recovery: 'actql-installed-row-effect-recovery/0.1', source: 'actql-installed-row-effect-source/0.1',
    targetCheck: 'actql-installed-row-effect-check/0.1', unit: 'actql-installed-row-effect-unit/0.1'};
  const original = issueUpdateTargetInstallation(moon, {binding_cid: 'sha256:' + 'c'.repeat(64),
    connection: 'fixture', connector_registration: 'update_target_fixture',
    connector_revision: 'update_target_fixture/0.1', continuation_binding: 'sha256:' + 'e'.repeat(64),
    profile, runtime_bundle_cid: 'sha256:' + 'd'.repeat(64)});
  assert.equal(original.cid, 'sha256:82b29228f604437218a51df3d6504e813219649a14e80c4b7c24f505eea6c1e9');
  assert.equal(installationsShape([original], moon), true);
  assert.equal(installationsShape([{...original, wire: original.wire.replace('fixture', 'foreign')}], moon), false);
  assert.equal(installationsShape([{...original, cid: 'sha256:' + 'f'.repeat(64)}], moon), false);
  assert.equal(installationsShape([original, original], moon), false);
});

test('normal codec generation checks the single Owner source and refuses generated drift', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-update-codec-'));
  try {
    for (const path of ['src/run_publication_host', 'src/remote_site_protocol', 'scripts/templates', 'adapters/host-node']) {
      await mkdir(join(root, path), {recursive: true});
    }
    for (const path of ['src/run_publication_host/client_effect_target_original_data.mbt',
      'src/remote_site_protocol/poll.mbt',
      'scripts/templates/update-target-data-codec.mjs']) {
      await writeFile(join(root, path), await readFile(new URL('../../' + path, import.meta.url)));
    }
    generateUpdateTargetDataCodec(root, true);
    generateUpdateTargetDataCodec(root);
    await writeFile(join(root, 'adapters/host-node/update-target-data.generated.mjs'), '// drift\n');
    assert.throws(() => generateUpdateTargetDataCodec(root), {message: 'Stale UPDATE transport codec'});
  } finally { await rm(root, {recursive: true, force: true}); }
});
