import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {projectOwnerSources} from '../../../scripts/interface-owner-source-projection.mjs';

for (const [owner, source, base, paths, all] of [
  ['f', '759af47f092ed3706d96d0b91b7684a33b39fa2a', '62c74f5d32e794d308b812919fc2d10b992f272c',
    ['packages/provider-http/_internal/*.mjs', 'packages/provider-ai-sdk/_internal/*.mjs',
      'scripts/generate-model-original-materials.mjs'], false],
  ['c', 'edc9bca8f11ebbd5bd79b04daa27e3e5d1bb4f0b', '02f9e53f29b4913d5c6e8276d2ac248800fe8173',
    ['adapters/connectors/sheets/host', 'adapters/connectors/sheets/site',
      'src/connectors/sheets/catalog/pkg.generated.mbti', 'src/connectors/sheets/host_node/pkg.generated.mbti'], true],
]) {
  test(`${owner} fixed owner blobs use the shared syntax inventory without product evaluation`, () => {
    const result = projectOwnerSources(process.cwd(), {source, base, paths, all});
    assert(result.modules.length);
    if (owner === 'f') assert.equal(result.modules.length, 12);
    if (owner === 'c') assert.equal(result.modules.filter(value => value.module.endsWith('.mbti')).length, 2);
    const readerSource = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
    writeFileSync(`/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/${owner}-owner-source-projection.json`,
      JSON.stringify({...result, readerSource}, null, 2) + '\n');
  });
}
