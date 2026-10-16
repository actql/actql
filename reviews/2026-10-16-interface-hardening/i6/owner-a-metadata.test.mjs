import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {assertInterfaceCoverage} from '../../../scripts/interface-inventory.mjs';

test('A fixed operation metadata and generated references cover its original syntax projection', () => {
  const directory = '/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/';
  const raw = readFileSync(directory + 'a-js-binding-interface-declarations.json');
  assert.equal(createHash('sha256').update(raw).digest('hex'),
    'af26ce83121c73470b61cac7143f1a3073e064315bbbf374e85621eae72439f7');
  const metadata = JSON.parse(raw);
  const syntaxRaw = readFileSync(directory + 'a-09e3-owner-source-projection.json');
  assert.equal(createHash('sha256').update(syntaxRaw).digest('hex'), metadata.syntaxProjectionSha256);
  const syntax = JSON.parse(syntaxRaw);
  const readReference = path => execFileSync('git', ['show', `${metadata.source}:${path}`],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  const checked = assertInterfaceCoverage({root: process.cwd(), modules: syntax.modules,
    declarations: metadata.declarations, generated: metadata.generated, readReference});
  assert.equal(checked, 53);
  writeFileSync(directory + 'a-js-binding-metadata-check.json', JSON.stringify({
    qualification: 'syntax-source coverage and fixed-reference check only',
    syntaxSource: metadata.syntaxSource, referencesSource: metadata.source,
    modules: checked, operations: syntax.modules.reduce((sum, value) => sum + value.operations.length, 0),
    targetTestsExecuted: 0,
  }, null, 2) + '\n');
});
