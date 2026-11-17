import assert from 'node:assert/strict';
import test from 'node:test';
import {validateNativeCliArtifactInputs} from './native-cli-ci-artifact.mjs';

const original = {ARTIFACT_ID: '101', ARTIFACT_RUN_ID: '42', ARTIFACT_RUN_ATTEMPT: '3',
  ARTIFACT_SOURCE_SHA: 'a'.repeat(40), EXPECTED_RUN_ID: '42', EXPECTED_RUN_ATTEMPT: '3',
  EXPECTED_SOURCE_SHA: 'a'.repeat(40)};

test('Native CLI consumers accept the exact original run attempt and source', () => {
  validateNativeCliArtifactInputs(original);
});

test('Native CLI consumers reject missing malformed and multiple artifact identities', () => {
  for (const key of ['ARTIFACT_ID', 'ARTIFACT_RUN_ID', 'ARTIFACT_RUN_ATTEMPT',
    'EXPECTED_RUN_ID', 'EXPECTED_RUN_ATTEMPT']) {
    for (const value of [undefined, '', '0', '-1', '101,102', ' 101', '101\n', 101]) {
      assert.throws(() => validateNativeCliArtifactInputs({...original, [key]: value}), undefined,
        `${key}: ${String(value)}`);
    }
  }
});

test('Native CLI consumers reject a foreign run attempt or source', () => {
  for (const changed of [{ARTIFACT_RUN_ID: '43'}, {ARTIFACT_RUN_ATTEMPT: '2'},
    {ARTIFACT_SOURCE_SHA: 'b'.repeat(40)}, {EXPECTED_RUN_ID: '43'},
    {EXPECTED_RUN_ATTEMPT: '4'}, {EXPECTED_SOURCE_SHA: 'b'.repeat(40)}]) {
    assert.throws(() => validateNativeCliArtifactInputs({...original, ...changed}));
  }
});

test('Native CLI consumers reject malformed source revisions on either side', () => {
  for (const key of ['ARTIFACT_SOURCE_SHA', 'EXPECTED_SOURCE_SHA']) {
    for (const value of [undefined, '', 'a'.repeat(39), 'A'.repeat(40), 'g'.repeat(40), 'a'.repeat(40) + '\n']) {
      assert.throws(() => validateNativeCliArtifactInputs({...original, [key]: value}));
    }
  }
});
