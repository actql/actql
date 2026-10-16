import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {projectOwnerSources} from '../../../scripts/interface-owner-source-projection.mjs';

test('A final two actual tuple consumers use the shared syntax and generated field access', () => {
  const source = '3e626100845be286750e71383ebaad29fcd71208';
  const paths = ['adapters/host-node/infer-raw-capture.mjs', 'packages/run-host-core/observation.mjs'];
  const result = projectOwnerSources(process.cwd(), {source, base: '02f9e53f29b4913d5c6e8276d2ac248800fe8173', paths, all: true});
  assert.equal(result.modules.length, 2);
  assert.deepEqual(result.modules.map(value => value.sha256), [
    '99561c228b553fff5b5a987c47854f45dc0b2f5071d0a78b2e6f8da58e363b02',
    '47c5920dcd16b65be41156686e7970adfd6b998d719c4e62420b0bef5f93887c']);
  assert(result.modules.every(value => value.compilerFields.length === 0));
  const readerSource = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  const bytes = JSON.stringify({...result, readerSource}, null, 2) + '\n';
  writeFileSync('/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/a-3e626-owner-source-projection.json', bytes);
  console.log(JSON.stringify({modules: 2, operations: result.modules.reduce((sum, value) => sum + value.operations.length, 0),
    sha256: createHash('sha256').update(bytes).digest('hex')}));
});
