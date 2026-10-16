import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {test} from 'node:test';
import ts from 'typescript';
import {typescriptInterfaceClosure} from '../../../scripts/typescript-interface-inventory.mjs';
import {interfaceOwnerCoverage} from '../../../scripts/interface-owner-coverage.mjs';

test('unchanged actual Wrangler closure matches original Cloud export references', () => {
  const root = process.env.ACTQL_I6_CLOUD_ROOT;
  assert(root, 'Select the original read-only Cloud source explicitly');
  const metadataPath = 'scripts/interface-owners/cloud-worker/interface-boundaries.json';
  const bytes = readFileSync(join(root, metadataPath));
  assert.equal(createHash('sha256').update(bytes).digest('hex'),
    '53f44975602e03a3215613639b171cb18beb9ac61768f9f7a74bcbb6ff018026');
  const config = ts.parseConfigFileTextToJson('wrangler.jsonc', readFileSync(join(root, 'wrangler.jsonc'), 'utf8'));
  assert.equal(config.error, undefined);
  assert.equal(typeof config.config.main, 'string');
  const modules = typescriptInterfaceClosure(root, [config.config.main]);
  const sidecar = JSON.parse(bytes);
  assert.equal(modules.length, 155);
  assert.equal(modules.reduce((count, module) => count + module.operations.length, 0), 3062);
  const result = interfaceOwnerCoverage({root, modules, owners: [{id: metadataPath,
    declarations: sidecar.declarations, qualification: sidecar.qualification}], generated: []});
  assert.equal(result.complete, true);
  assert.equal(result.covered, 155);
  const source = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  const cloudSource = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  const record = {source, cloudSource, qualification: 'actual Cloud source/reference coverage only',
    normalCohort: 'not-verified', allI6: 'incomplete', newProductE2E: 0,
    entry: config.config.main, sidecarSha256: createHash('sha256').update(bytes).digest('hex'), result, modules};
  writeFileSync(`/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/b-cloud-binding-exports-${source.slice(0, 12)}.json`,
    JSON.stringify(record, null, 2) + '\n');
});
