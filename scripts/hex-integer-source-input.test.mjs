import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {hexIntegerProgram, hexIntegerSuccesses, hexIntegerRefusals} from './fixtures/hex-integer-source-input.mjs';

test('hex integer public expectations distinguish value positions limits and duplicates', () => {
  assert.equal(hexIntegerSuccesses.length, 8);
  assert.equal(hexIntegerRefusals.length, 6);
  assert.deepEqual(hexIntegerProgram.stages[0].steps[1].derive, {value: {literal: 16}});
  assert.deepEqual(hexIntegerSuccesses.find(item => item.name.endsWith('scalars')).expected,
    [{zero: 0, positive: 16, negative: -31, maximum: 9007199254740991}]);
  assert.equal(BigInt('0x1fffffffffffff'), 9007199254740991n);
  assert.equal(BigInt('0x20000000000000'), 9007199254740992n);
  assert.deepEqual(hexIntegerSuccesses.find(item => item.name.endsWith('set-position-limit-offset')).expected,
    [{id: 1}, {id: 2}]);
  assert.deepEqual(hexIntegerSuccesses.find(item => item.name.endsWith('empty-typed')).columns,
    [{name: 'value', contract: {type: 'number', nullable: false}}]);
  const signedZero = hexIntegerSuccesses.find(item => item.name === 'hex-integer-signed-zero');
  assert.equal(signedZero.text, 'SELECT -0X0 AS value');
  assert.deepEqual(signedZero.expected, [{value: 0}]);
  assert.equal(Object.is(signedZero.expected[0].value, -0), false);
  assert.deepEqual(signedZero.columns, [{name: 'value', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(hexIntegerRefusals.map(item => item.name),
    [0, 1, 2, 3, 5, 6].map(index => 'hex-integer-refuse-' + index));
  const items = [...hexIntegerSuccesses, ...hexIntegerRefusals];
  assert.equal(new Set(items.map(item => item.name)).size, items.length);
});

test('hex integer fixtures enter the ordinary and existing narrow packed paths', () => {
  const consumer = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(consumer.includes('scopeInputs.successes.push(...hexIntegerSuccesses)'));
  assert.ok(consumer.includes('scopeInputs.refusals.push(...hexIntegerRefusals)'));
  assert.ok(consumer.includes('hexIntegerOnly ? {successes: hexIntegerSuccesses, refusals: hexIntegerRefusals}'));
  const selectors = consumer.match(/const scopeOnly = ([^;]+);/u)?.[1];
  assert.ok(selectors);
  assert.equal(selectors.split(/\s*\|\|\s*/u).filter(term => term === 'hexIntegerOnly').length, 1);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_HEX_INTEGER_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/hex-integer-source-input.mjs', 'hex-integer-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = [^;]*'--hex-integer-only'/u);
  assert.ok(driver.includes("process.argv.includes('--hex-integer-only')) return;"));
});
