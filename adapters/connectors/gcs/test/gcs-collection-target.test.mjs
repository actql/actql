// Actual compiled provider semantics and private DATA bridge, not installed
// Common reference admission, Effect authorization, Store ACK or service I/O.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {prepareGcsCollectionTarget, checkGcsCollectionTarget} from '../host/gcs-collection-target.mjs';

const cid = value => `sha256:${value.repeat(64)}`;
const config = overrides => ({project: 'project', bucket: 'bucket', prefix: 'in/é%2F/',
  targetRef: 'connector://exports/objects', resourceKind: 'file_collection',
  catalogCid: cid('a'), installationCid: cid('b'),
  maxBytes: 4096, maxNodes: 100, maxDepth: 8, ...overrides});

test('real GCS collection uses the independent complete Mapping identity vector', () => {
  const target = prepareGcsCollectionTarget(moon, config());
  assert.equal(target.identityWire, '{"boundary_topology":"connector_connection","collection_identity":{"bucket":"bucket","prefix":"in/é%2F/","project":"project"},"provider_namespace":"gcs","resource_kind":"file_collection","target_ref":"connector://exports/objects","version":"actql.collection_resource_identity/0.1"}');
  assert.equal(target.identityCid, 'sha256:d0f85fdad35ae5bd456d1c37343895dd1ba0c1de01887c5de5bda439e9b13e62');
  assert.equal(target.resourceWire, '{"$actql_ref":"resource","authority_scope_cid":"sha256:43d874820e0b878c597abc58ac3795db2e39e66e54fe479ba8ee803532515bd2","boundary_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","identity_cid":"sha256:d0f85fdad35ae5bd456d1c37343895dd1ba0c1de01887c5de5bda439e9b13e62","provider_identity_cid":"sha256:bdef7723e3c39d7e7d6feb66d1bd8ab7a2b2f1c000d631f4370297e6832e110a","provider_namespace":"gcs","resource_kind":"file_collection","version":"actql-resource-ref/0.1"}');
  assert.ok(Object.isFrozen(target));
  assert.equal(target.referenceIssuer, undefined);
});

test('same data, copied projections and foreign provider namespace cannot borrow original binding', () => {
  const target = prepareGcsCollectionTarget(moon, config());
  const equal = prepareGcsCollectionTarget(moon, config());
  assert.deepEqual(equal, target);
  checkGcsCollectionTarget(target, target, cid('b'), 'connector://exports/objects');
  assert.throws(() => checkGcsCollectionTarget(target, equal, cid('b'),
    'connector://exports/objects'), {code: 'GcsForeignCollectionBinding'});
  assert.throws(() => checkGcsCollectionTarget(target, {...target}, cid('b'),
    'connector://exports/objects'), {code: 'ForeignGcsCollectionTarget'});
  const otherNamespace = prepareGcsCollectionTarget({...moon}, config());
  assert.throws(() => checkGcsCollectionTarget(target, otherNamespace, cid('b'),
    'connector://exports/objects'), {code: 'ForeignGcsCollectionTarget'});
});

test('current installation and selected target facts cannot be exchanged for an equal resource wire', () => {
  const target = prepareGcsCollectionTarget(moon, config());
  const installedElsewhere = prepareGcsCollectionTarget(moon, config({installationCid: cid('c')}));
  assert.deepEqual(installedElsewhere, target);
  for (const [installation, ref] of [[cid('c'), 'connector://exports/objects'],
    [cid('b'), 'connector://reader_alias/objects']]) {
    assert.throws(() => checkGcsCollectionTarget(target, target, installation, ref),
      {code: 'GcsForeignCollectionBinding'});
  }
  const catalogChanged = prepareGcsCollectionTarget(moon, config({catalogCid: cid('c')}));
  assert.equal(catalogChanged.identityCid, target.identityCid);
  assert.notEqual(catalogChanged.resourceWire, target.resourceWire);
});

test('prefix, provider, kind and explicit target retain exact non-normalized identities', () => {
  const original = prepareGcsCollectionTarget(moon, config());
  for (const change of [{prefix: 'in/é%2F/'}, {prefix: 'in/é//'},
    {bucket: 'other'}, {project: 'other'}, {targetRef: 'connector://other/objects'},
    {resourceKind: 'file'}]) {
    assert.notEqual(prepareGcsCollectionTarget(moon, config(change)).identityCid,
      original.identityCid);
  }
});

test('typed boundary checks limits before compiler Int truncation and refuses one-short output', () => {
  let calls = 0;
  const observed = {...moon, gcsCollectionBinding(...args) {
    calls++;
    return moon.gcsCollectionBinding(...args);
  }};
  for (const value of [0, -1, 0.5, 2 ** 32 + 4096, Number.MAX_SAFE_INTEGER, Infinity]) {
    assert.throws(() => prepareGcsCollectionTarget(observed, config({maxBytes: value})),
      {code: 'InvalidGcsCollectionAbiLimits'});
  }
  assert.equal(calls, 0);
  const original = prepareGcsCollectionTarget(moon, config());
  const bytes = Buffer.byteLength(original.resourceWire);
  assert.deepEqual(prepareGcsCollectionTarget(moon, config({maxBytes: bytes})), original);
  assert.throws(() => prepareGcsCollectionTarget(moon, config({maxBytes: bytes - 1})),
    {code: 'GcsCollectionCapacityExceeded'});
});
