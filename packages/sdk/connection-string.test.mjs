import test from 'node:test';
import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {parseConnectionString, connectionStringCredential} from
  './connection-string.mjs';

test('connection strings separate a bearer credential from the HTTPS target', () => {
  const secret = 'example:+/@?#%credential';
  const value = parseConnectionString(
    `actql://token:${encodeURIComponent(secret)}@EXAMPLE.test:8443/ws_0123`);
  assert.deepEqual(value, {endpoint: 'https://example.test:8443/',
    workspaceId: 'ws_0123'});
  assert.equal(connectionStringCredential(value), secret);
  assert.equal(Object.isFrozen(value), true);
  for (const output of [JSON.stringify(value), inspect(value),
    inspect(value, {showHidden: true}), String(value)]) {
    assert.equal(output.includes(secret), false);
    assert.equal(output.includes(encodeURIComponent(secret)), false);
    assert.equal(output.includes('token:'), false);
  }
  assert.equal(connectionStringCredential({...value}), undefined);
  assert.equal(connectionStringCredential(structuredClone(value)), undefined);
});

test('credentialless connection strings preserve an exact opaque workspace ID', () => {
  for (const [input, expected] of [
    ['actql://example.test/workspace', 'workspace'],
    ['ACTQL://example.test:443/Case-Sensitive', 'Case-Sensitive'],
    ['actql://example.test/%E6%9D%B1%E4%BA%AC%20workspace', '東京 workspace'],
    ['actql://example.test/a%253Ab', 'a%3Ab'],
    ['actql://example.test/space%3Fname%23suffix', 'space?name#suffix'],
  ]) {
    const value = parseConnectionString(input);
    assert.equal(value.endpoint, 'https://example.test/');
    assert.equal(value.workspaceId, expected);
    assert.equal(connectionStringCredential(value), undefined);
  }
});

test('network localhost and IPv6 remain explicit HTTPS network targets', () => {
  assert.deepEqual(parseConnectionString('actql://localhost/local'),
    {endpoint: 'https://localhost/', workspaceId: 'local'});
  assert.deepEqual(parseConnectionString('actql://[::1]:8443/local'),
    {endpoint: 'https://[::1]:8443/', workspaceId: 'local'});
});

test('credentials decode once and never introduce URL structure', () => {
  const value = parseConnectionString(
    'actql://token:raw%2540%3A%2F%3F%23@example.test/workspace');
  assert.equal(connectionStringCredential(value), 'raw%40:/?#');
  assert.equal(value.endpoint, 'https://example.test/');
});

test('invalid connection strings never disclose their input or parser cause', () => {
  const privatePart = 'DO_NOT_DISCLOSE';
  const invalidInputs = [undefined, null, {}, 1, Symbol('private'),
    'https://example.test/workspace', 'actql://example.test',
    'actql://example.test/', 'actql://example.test/a/b',
    'actql://example.test/a/../b', 'actql://example.test/.',
    'actql://example.test/%2e%2e', 'actql://example.test/a%2Fb',
    'actql://example.test/a%5Cb', 'actql://example.test/a%00b',
    'actql://example.test/%ff', 'actql://example.test/a%2',
    'actql://example.test/a?sslmode=require', 'actql://example.test/a#b',
    'actql://example.test/white space', ' actql://example.test/a',
    'actql://example.test/a\n', 'actql://example.test/a\ud800',
    'actql://example.test/%ED%A0%80', 'actql://%65xample.test/a',
    'actql://example.test:70000/a', 'actql://[not-ipv6]/a',
    `actql://token:${privatePart}@example.test/a?token=hidden`,
    `actql://token:${privatePart}@example.test@other.test/a`,
    `actql://person:${privatePart}@example.test/a`,
    `actql://to%6Ben:${privatePart}@example.test/a`,
    `actql://token:${privatePart}:tail@example.test/a`,
    `actql://token:${privatePart}%0d%0a@example.test/a`,
    `actql://token:${privatePart}%20tail@example.test/a`,
    `actql://token:${privatePart}%GG@example.test/a`,
    'actql://token:%E6%9D%B1%E4%BA%AC@example.test/a',
    'actql://token:@example.test/a', 'actql://@example.test/a',
    'actql://token:secret@/a', 'actql://token:secret@a\\b/a',
    `actql://example.test/${'a'.repeat(257)}`,
    `actql://token:${'a'.repeat(8193)}@example.test/a`,
    `actql://token:${'%61'.repeat(6000)}@example.test/a`,
  ];
  for (const input of invalidInputs) {
    let failure;
    try { parseConnectionString(input); }
    catch (error) { failure = error; }
    assert.ok(failure instanceof TypeError);
    assert.equal(failure.message, 'InvalidConnectionString');
    assert.equal(failure.cause, undefined);
    assert.equal(Object.hasOwn(failure, 'input'), false);
    for (const output of [JSON.stringify(failure), inspect(failure),
      inspect(failure, {showHidden: true}), failure.stack]) {
      assert.equal(output.includes(privatePart), false);
    }
  }
});
