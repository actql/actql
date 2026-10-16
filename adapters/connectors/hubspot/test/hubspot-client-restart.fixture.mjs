// Fresh process over the original test Host/Run; never a re-preparation recipe.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {connectEmbeddedLocal} from '../../../host-node/embedded-local.mjs';
const {installation, ref} = JSON.parse(await readFile(process.argv[2], 'utf8'));
let secretResolutions = 0;
const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
  durability: 'durable', installation: {...installation,
    resolveSourceSecret() {
      secretResolutions++;
      throw new Error('UnexpectedOriginalHubSpotReplay');
    }}});
try {
  const execution = await client.attach(ref);
  assert.deepEqual(execution.ref, ref);
  const state = await execution.status();
  assert.equal(state.status, 'succeeded');
  const result = execution.result('records');
  const columns = (await result.describe()).columns;
  const rows = await result.all();
  assert.equal(secretResolutions, 0);
  process.stdout.write(JSON.stringify({sameRun: true, secretResolutions, columns, rows}));
} finally {await client.close();}
