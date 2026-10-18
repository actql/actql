// Physical cold-read probe only. The caller supplies an explicit semantic
// binding fixture, not an installation observation, grant or Common issuer.
import {createHash} from 'node:crypto';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

const {configuration, binding, keyByte} = JSON.parse(process.argv[2]);
const store = await openLocalPublicationStore({...configuration,
  privateEvidenceKey: keyByte === null ? undefined : Buffer.alloc(32, keyByte)},
createPublicationContractControlFixture());
try {
  const bytes = await store.readPrivateEvidence(binding.name,
    binding.semanticCid, binding.holdingCid);
  const record = await store.confirmPrivateEvidence({...binding, wire: bytes.toString('utf8')});
  console.log(JSON.stringify({pid: process.pid,
    bytes: bytes.byteLength,
    digest: createHash('sha256').update(bytes).digest('hex'),
    holdingCid: record.holding_cid}));
} finally {
  if (await store.close() !== true) throw new Error('ColdPublicationStoreClosePending');
}
