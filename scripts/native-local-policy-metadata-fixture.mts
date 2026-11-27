// Source-bound test input only; no custody, Policy or admission is manufactured.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {gunzipSync} from 'node:zlib';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
export function policyMetadataFixture() {
  const input=gunzipSync(readFileSync(resolve(root,'scripts/fixtures/native-local-policy-projection/old109-run.json.gz')));
  assert.equal(input.length,45018);
  assert.equal(createHash('sha256').update(input).digest('hex'),'f4a9b5e68b66f4d0818431e49e070258ee6438676628e0126021c1e04e7e5b50');
  return '// Retained exact old109 run.json input; not adoption custody or authority.\n\n///|\nfn local_policy_metadata_old109_run_wire() -> String {\n  '+JSON.stringify(input.toString('utf8'))+'\n}\n';
}
const file=resolve(root,'src/run_publication_host/client_local_run_policy_metadata_fixture.generated_wbtest.mbt');
if (process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  assert(process.argv.length===3 && ['--check','--write'].includes(process.argv[2]));
  if(process.argv[2]==='--write') writeFileSync(file,policyMetadataFixture());
  else assert.equal(readFileSync(file,'utf8'),policyMetadataFixture());
}
