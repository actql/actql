// Preparation/closure controls only. These do not start a Host or a provider.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dirname, posix} from 'node:path';
import test from 'node:test';
import {parse} from 'acorn';
import {sheetsPackedSelection, sheetsPackedFixturePaths} from './sheets-packed-cases.mjs';

test('Sheets release keeps all fourteen original and two range declarations by default', () => {
  const selection = sheetsPackedSelection([]);
  assert.equal(selection.expectedTests, 16);
  assert.equal(selection.directory, undefined);
  assert.equal(selection.rangeOnly, false);
  assert.deepEqual(selection.testArguments,
    ['adapters/connectors/sheets/test/sheets-packed.fixture.mjs']);
  assert(Object.isFrozen(selection)); assert(Object.isFrozen(selection.testArguments));
});

test('Sheets release narrows only the two existing range Commands with a supplied normal cohort', () => {
  const selection = sheetsPackedSelection(['--range-command-only', '--release-dir', '/fixture/release']);
  assert.equal(selection.directory, '/fixture/release');
  assert.equal(selection.expectedTests, 2);
  assert.deepEqual(selection.testArguments, ['--test-name-pattern=^Sheets range Command',
    'adapters/connectors/sheets/test/sheets-packed.fixture.mjs']);
  assert.equal(sheetsPackedSelection(['--release-dir', '/fixture/release']).expectedTests, 16);
});

test('Sheets release refuses ambiguous selectors instead of starting another producer or widening cases', () => {
  for (const args of [['--range-command-only'], ['--release-dir'],
    ['--release-dir', 'relative'], ['--release-dir', '/one', '--release-dir', '/two'],
    ['--range-command-only', '--range-command-only', '--release-dir', '/one'],
    ['--skip-source'], ['--release-dir=/fixture/release'],
    ['--range-command-only', '--release-dir', '/one', '--all']]) {
    assert.throws(() => sheetsPackedSelection(args));
  }
});

test('Sheets release inventory covers the actual declarations and every copied relative import', () => {
  const repository = new URL('../', import.meta.url);
  const publicFixture = 'adapters/connectors/sheets/test/sheets-public-acceptance.fixture.mjs';
  const names = [];
  function visit(node, repetitions = 1) {
    if (node.type === 'ExpressionStatement' && node.expression.type === 'CallExpression' &&
        node.expression.callee.type === 'Identifier' && node.expression.callee.name === 'test') {
      names.push({node: node.expression.arguments[0], repetitions}); return;
    }
    if (node.type === 'ForOfStatement') {
      // Only registration loops matter; loops inside test callbacks are not
      // separate Node tests and were excluded at the CallExpression above.
      assert.equal(node.right.type, 'ArrayExpression');
      visit(node.body, repetitions * node.right.elements.length); return;
    }
    if (node.type === 'BlockStatement') {
      for (const child of node.body) visit(child, repetitions);
    }
  }
  const ast = parse(readFileSync(new URL(publicFixture, repository), 'utf8'),
    {ecmaVersion: 'latest', sourceType: 'module'});
  const registration = ast.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.id?.name === 'registerSheetsAcceptance');
  assert(registration);
  visit(registration.declaration.body);
  assert.equal(names.reduce((count, item) => count + item.repetitions, 0), 16);
  assert.deepEqual(names.filter(({node}) => node.type === 'Literal' &&
    node.value.startsWith('Sheets range Command')).map(({node}) => node.value), [
    'Sheets range Command uses the real Local and HTTPS approval owners and original saved request',
    'Sheets range Command retains an unknown acknowledgement across process restart without resend',
  ]);
  const copied = new Set(sheetsPackedFixturePaths);
  assert.equal(copied.size, 7);
  const owned = new Set(['@actql/node', '@actql/sdk', '@actql/sdk/host-port',
    '@actql/local-node', '@actql/local-node/http-host']);
  for (const path of copied) {
    const file = parse(readFileSync(new URL(path, repository), 'utf8'),
      {ecmaVersion: 'latest', sourceType: 'module'});
    for (const node of file.body) if (['ImportDeclaration', 'ExportNamedDeclaration',
      'ExportAllDeclaration'].includes(node.type) && node.source) {
      const specifier = node.source.value;
      if (specifier.startsWith('.')) {
        assert(copied.has(posix.normalize(posix.join(dirname(path), specifier))),
          `Unshipped relative fixture: ${path} -> ${specifier}`);
      } else assert(specifier.startsWith('node:') || owned.has(specifier),
        `Unexpected product/ambient import: ${specifier}`);
    }
  }
});
