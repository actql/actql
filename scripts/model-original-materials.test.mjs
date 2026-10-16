import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

test('optional Model material loaders retain one closed DATA source and explicit SDK branches', () => {
  const source = readFileSync(new URL('../adapters/host-common/model-original-materials.mjs.in', import.meta.url), 'utf8');
  assert.equal(source.split('__SDK_FIELD__').length, 2);
  for (const [name, provider, sdk] of [
    ['provider-ai-sdk', 'OpenAI', "sdk:shape('interface,lock_artifact_cid,package_name,version'),"],
    ['provider-http', 'HTTP', 'sdk:value => {if (value !== null) fail();return value;},'],
  ]) {
    const expected = source.replaceAll('__PROVIDER__', provider).replace('__SDK_FIELD__', sdk);
    assert.equal(readFileSync(new URL(`../packages/${name}/_internal/original-materials.mjs`, import.meta.url), 'utf8'), expected);
  }
});
