import assert from 'node:assert/strict';
import {cpSync, mkdirSync, mkdtempSync, unlinkSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {assertClientWireDependency} from
  './connector-addition-wire-dependency.mjs';

test('isolated Host requires the generated Client wire closure', () => {
  const root = process.cwd();
  const artifacts = join(root, '.artifacts');
  mkdirSync(artifacts, {recursive: true});
  const isolated = mkdtempSync(join(artifacts, 'wire-dependency-'));
  mkdirSync(join(isolated, 'packages'), {recursive: true});
  cpSync(join(root, 'packages/client-wire'),
    join(isolated, 'packages/client-wire'), {recursive: true});
  assertClientWireDependency(isolated);
  unlinkSync(join(isolated,
    'packages/client-wire/client-host.generated.js'));
  assert.throws(() => assertClientWireDependency(isolated),
    /MissingClientWireDependency:client-host\.generated\.js/u);
});
