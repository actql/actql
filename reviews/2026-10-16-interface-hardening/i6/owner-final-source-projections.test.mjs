import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {projectOwnerSources} from '../../../scripts/interface-owner-source-projection.mjs';

const base = '02f9e53f29b4913d5c6e8276d2ac248800fe8173';
const cases = [
  {owner: 'a-f2df', source: 'f2dfef8b56340838832eb5347734deeb85596788',
    base: 'd7fdc2d09928591aecc29db8773b0a6e1a0e3e38', paths: ['adapters', 'packages'], count: 8},
  {owner: 'c-12db', source: '12db5b0ca3270a72e7efbdfa37005182926b4ea8',
    base: 'edc9bca8f11ebbd5bd79b04daa27e3e5d1bb4f0b', count: 4,
    paths: ['adapters/connectors/sheets/host/sheets-range-command.mjs',
      'adapters/connectors/sheets/site/sheets-exchange.mjs',
      'src/connectors/sheets/catalog/pkg.generated.mbti', 'src/connectors/sheets/host_node/pkg.generated.mbti']},
  {owner: 'f-a15', source: 'a15da975efd8303a997c3b8395ae9f7bd4e3dca7', base, all: true, count: 16,
    paths: [
      ...['credential-scope-fields.generated', 'owned-invocation-context', 'sqlite-transaction',
        'observation', 'task-observation', 'diagnostic-observer'].map(name => `adapters/host-common/${name}.mjs`),
      ...['https-credential-resource', 'sqlite-credential-journal', 'sqlite-dispatch-journal',
        'sqlite-transfer-journal'].map(name => `adapters/site-node/${name}.mjs`),
      ...['sqlite-coordinator-journal', 'remote-site-coordinator', 'infer-entry-persistence',
        'infer-raw-capture', 'infer-capture-custody', 'infer-physical-observation']
        .map(name => `adapters/host-node/${name}.mjs`)]},
];

for (const item of cases) {
  test(`${item.owner} immutable syntax projection preserves the prior owner evidence`, () => {
    const result = projectOwnerSources(process.cwd(), item);
    assert.equal(result.modules.length, item.count);
    const readerSource = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
    const bytes = JSON.stringify({...result, readerSource}, null, 2) + '\n';
    const path = `/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/${item.owner}-owner-source-projection.json`;
    writeFileSync(path, bytes);
    console.log(JSON.stringify({owner: item.owner, modules: result.modules.length,
      operations: result.modules.reduce((sum, value) => sum + value.operations.length, 0),
      sha256: createHash('sha256').update(bytes).digest('hex')}));
  });
}
