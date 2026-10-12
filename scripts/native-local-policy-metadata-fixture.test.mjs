import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {policyMetadataFixture} from './native-local-policy-metadata-fixture.mjs';

test('actual retained old109 policy fixture keeps full compute bodies and source identity', () => {
  const raw=gunzipSync(readFileSync('scripts/fixtures/native-local-policy-projection/old109-run.json.gz'));
  assert.equal(raw.length,45018);
  assert.equal(createHash('sha256').update(raw).digest('hex'),'f4a9b5e68b66f4d0818431e49e070258ee6438676628e0126021c1e04e7e5b50');
  const fields=JSON.parse(raw).native.run.source_free;
  assert.equal(Buffer.byteLength(fields.values),9241);
  assert.equal(Buffer.byteLength(fields.ordered),21855);
  assert.equal(fields.result_policy_cid,'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563');
  assert.equal(readFileSync('src/run_publication_host/client_local_run_policy_metadata_fixture.generated_wbtest.mbt','utf8'),policyMetadataFixture());
});
