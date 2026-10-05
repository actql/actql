// One Embedded Local step over a cross-version installation, in its own
// process (each process opens the Embedded Local Host afresh, so consecutive
// steps are Host restarts): `submit` holds the Set and saves its ref,
// `answer` approves it as the local owner, `resume` lets the Host continue it
// and waits to be killed.
import {createPrivateKey, sign} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {connectEmbeddedLocal} from '../../../../host-node/embedded-local.mjs';
import {hostAuthorization, secret, waitFor} from './update-state.mjs';

const {installation, orgId, keys, step, program, refPath} = JSON.parse(
  process.env.ACTQL_CROSS_VERSION_LOCAL);
const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
  durability: 'durable', installation: {
    directory: installation.directory,
    sourceProfilePath: installation.sourceProfilePath,
    resolveSourceSecret: secret,
    effectProfilePath: installation.effectProfilePath,
    resolveEffectSecret: secret,
    authorization: hostAuthorization(orgId, keys, {local: true})}});
if (step === 'submit') {
  const execution = await client.aql(program, {format: 'json',
    requestId: 'cross-version-update'});
  await waitFor(async () => (await execution.status()).status ===
    'waiting_checkpoint');
  writeFileSync(refPath, JSON.stringify(execution.ref));
  process.exit(0);
} else if (step === 'answer') {
  const ref = JSON.parse(readFileSync(refPath, 'utf8'));
  const [checkpoint] = (await client.checkpoints()).items;
  const key = createPrivateKey(keys.reviewerPrivate);
  const answer = await client.resolveCheckpoints([{checkpoint,
    decision: 'approved'}], {signer: {keyId: 'reviewer-key',
    reviewerId: 'reviewer', authorityScopeCid: ref.authorityScopeCid,
    sign: bytes => sign(null, bytes, key)}});
  process.exit(answer.results[0]?.status === 'committed' ? 0 : 1);
} else if (step === 'resume') {
  const ref = JSON.parse(readFileSync(refPath, 'utf8'));
  await client.attach(ref);
  console.log('local-resumed');
  setInterval(() => {}, 1 << 30);
} else {
  process.exit(2);
}
