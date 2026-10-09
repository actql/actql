// One step of the public Read→Compute→Effect acceptance, in its own process.
// Local and trusted HTTPS use the same installed owner; consecutive steps
// begin after the original child exits. Arguments: step, then installation path.
import assert from 'node:assert/strict';
import {createPrivateKey, sign} from 'node:crypto';
import {appendFileSync, readFileSync, writeFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import * as sdk from '../../../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from '../../../host-node/embedded-local.mjs';

const [step, installationPath] = process.argv.slice(2);
const installation = JSON.parse(readFileSync(installationPath, 'utf8'));
// A test fault: the first close of a journal of this module fails.
const faultModule = process.env.ACTQL_EMBEDDED_FAIL_FIRST_CLOSE;
const closes = {attempts: 0, failed: 0};
if (faultModule !== undefined) {
  const original = DatabaseSync.prototype.close;
  DatabaseSync.prototype.close = function () {
    if (new Error().stack.includes(faultModule)) {
      closes.attempts++;
      if (closes.failed === 0) {
        closes.failed++;
        throw new Error('InjectedJournalCloseFailure');
      }
    }
    return original.call(this);
  };
}
const secret = async () => 'test-only-secret';
const diagnostics = [];
const installed = {
  directory: installation.directory,
  sourceProfilePath: installation.sourceProfilePath,
  resolveSourceSecret: secret,
  effectProfilePath: installation.effectProfilePath,
  resolveEffectSecret: secret,
  authorization: {...installation.authorization,
    observe: (name, detail) => {
      const event = {pid: process.pid, name, code: detail?.code};
      diagnostics.push({name, code: detail?.code});
      // Test observations are separate from the Owner's durable receipts.
      appendFileSync(`${installationPath}.owner-observations.jsonl`,
        JSON.stringify(event) + '\n', {mode: 0o600});
    }},
};
let client, host, server;
let httpsRequests = 0;
if (installation.transport === 'https') {
  const cert = readFileSync(installation.hostTls.certificatePath);
  setDefaultCACertificates([...getCACertificates('default'), cert.toString('utf8')]);
  host = await openInstalledRemoteHttpHost({...installed,
    authenticate: header => header === 'Bearer owner-token' ? userInfo().username : undefined});
  server = createServer({key: readFileSync(installation.hostTls.keyPath), cert}, (request, response) => {
    httpsRequests++;
    host.handler(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  client = await sdk.connect({mode: 'remote', durability: 'durable', token: 'owner-token',
    endpoint: `https://127.0.0.1:${server.address().port}/`});
} else {
  client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    durability: 'durable', installation: installed});
}
async function waitFor(check) {
  for (let attempt = 0; attempt < 400; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('EmbeddedStepTimeout');
}
const refPath = `${installationPath}.ref.json`;
const submissionPath = `${installationPath}.submission-ref.json`;
try {
  if (step === 'submit') {
    const submissionRef = client.newSubmission({nonce: installation.requestId});
    writeFileSync(submissionPath, JSON.stringify(submissionRef) + '\n',
      {flag: 'wx', mode: 0o600});
    let execution;
    try {
      execution = await client.startSource(installation.program, {format: 'json',
        submissionRef});
    } catch (error) {
      if (error?.code === 'ClientProgramUnsupported') {
        console.log(JSON.stringify({notConnected: true}));
        process.exit(0);
      }
      throw error;
    }
    await waitFor(async () => (await execution.status()).status ===
      'waiting_checkpoint');
    writeFileSync(refPath, JSON.stringify(execution.ref), {flag: 'wx', mode: 0o600});
    console.log(JSON.stringify({held: true}));
  } else if (step === 'answer') {
    const ref = JSON.parse(readFileSync(refPath, 'utf8'));
    const [checkpoint] = (await client.checkpoints()).items;
    assert.equal(checkpoint.kind, 'effect_set');
    const key = createPrivateKey(installation.reviewerPrivateKey);
    const answer = await client.resolveCheckpoints([
      {checkpoint, decision: 'approved'}], {signer: {keyId: 'reviewer-key',
      reviewerId: 'reviewer', authorityScopeCid: ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, key)}});
    console.log(JSON.stringify({answered: answer.results.map(item =>
      item.status)}));
  } else if (step === 'resume') {
    const ref = JSON.parse(readFileSync(refPath, 'utf8'));
    const submissionRef = JSON.parse(readFileSync(submissionPath, 'utf8'));
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready');
    assert.deepEqual(lookup.submissionRef, submissionRef);
    assert.deepEqual(lookup.admission.ref, ref);
    const execution = await client.attach(ref);
    const state = await waitFor(async () => {
      const current = await execution.status();
      return ['succeeded', 'failed', 'needs_reconciliation', 'cancelled']
        .includes(current.status) ? current : undefined;
    });
    const rows = state.status === 'succeeded'
      ? await execution.result(installation.resultName ?? 'updates').all()
      : undefined;
    // Wait for the Run's physical work and cleanup to be confirmed stopped.
    await waitFor(async () => (await execution.status()).control
      ?.physical_stop === 'confirmed');
    console.log(JSON.stringify({status: state.status, rows,
      ...(faultModule === undefined ? {} : {closes})}));
  } else if (['observe-owners','replay-owners','cursor-cases','partial-owners'].includes(step)) {
    const ref=JSON.parse(readFileSync(refPath,'utf8'));
    const submissionRef=JSON.parse(readFileSync(submissionPath,'utf8'));
    const lookup=await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind,'ready');assert.deepEqual(lookup.admission.ref,ref);
    const execution=await client.attach(lookup.admission.ref);
    const savedPath=refPath+'.owner-cursors.json';
    const cursors=step==='observe-owners' || step==='partial-owners' ? [] : JSON.parse(readFileSync(savedPath,'utf8'));
    const options={cursors,maxEntries:1,maxWireBytes:65536};
    if(step==='cursor-cases'){
      const [cursor]=cursors;
      const claim=JSON.parse(Buffer.from(cursor.value.split('.')[0],'base64url').toString('utf8'));
      const signed=modified=>{
        const bytes=Buffer.from(JSON.stringify(modified),'utf8');
        return {owner:cursor.owner,value:`${bytes.toString('base64url')}.${sign(null,bytes,
          createPrivateKey(installation.authorization.hostKey.privateKey)).toString('base64url')}`};
      };
      const expired=await execution.observeOwners({...options,cursors:[signed({...claim,expiresAt:1})]});
      const foreign=await execution.observeOwners({...options,cursors:[signed({...claim,
        ref:{...ref,runDefinitionCid:`sha256:${'0'.repeat(64)}`}})]});
      const changed=await execution.observeOwners({...options,cursors:[{...cursor,value:cursor.value+'x'}]});
      const unbound=await execution.observeOwners({...options,cursors:[{...cursor,
        owner:{...cursor.owner,streamCid:`sha256:${'0'.repeat(64)}`}}]});
      console.log(JSON.stringify({pid:process.pid,ref,expired,foreign,changed,unbound,state:await execution.status()}));
    }else{
    const prepare=DatabaseSync.prototype.prepare;
    // Fault exactly the inventory read, after Host initialization and original
    // Submission lookup. Other Owners remain usable in this child process.
    if(step==='partial-owners')DatabaseSync.prototype.prepare=function(sql){
      if(sql.includes('WHERE h.logical_request_scope_cid=?'))throw new Error('PRIVATE_INVENTORY_FAILURE');
      return prepare.call(this,sql);
    };
    let views;
    try{views=await execution.observeOwners(options);}
    finally{DatabaseSync.prototype.prepare=prepare;}
    if(step==='observe-owners')writeFileSync(savedPath,JSON.stringify(views.owners
      .filter(view=>view.history?.cursor!==undefined).map(view=>view.history.cursor)),{mode:0o600,flag:'wx'});
    console.log(JSON.stringify({pid:process.pid,transport:server?'https':'local',httpsRequests,ref,views,
      state:await execution.status()}));
    }
  } else if (step === 'observe-effect') {
    const ref = JSON.parse(readFileSync(refPath, 'utf8'));
    const submissionRef = JSON.parse(readFileSync(submissionPath, 'utf8'));
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready');
    assert.deepEqual(lookup.submissionRef, submissionRef);
    assert.deepEqual(lookup.admission.ref, ref);
    const execution = await client.attach(lookup.admission.ref);
    const state = await waitFor(async () => {
      const current = await execution.status();
      return current.status === 'needs_reconciliation' && current.control?.physical_stop === 'confirmed'
        ? current : undefined;
    });
    let reconciled, reconcileError;
    try { reconciled = await execution.reconcile(); }
    catch (error) { reconcileError = error.code; }
    console.log(JSON.stringify({pid: process.pid, transport: server ? 'https' : 'local', httpsRequests,
      ref, state, reconcileError, reconciled, diagnostics,
      reconciledExplanation: sdk.explainEffectUncertainty?.(reconciled),
      explanation: sdk.explainEffectUncertainty?.(state),
      japaneseExplanation: sdk.explainEffectUncertainty?.(state, {locale: 'ja'}),
      copiedExplanation: sdk.explainEffectUncertainty?.({...state}),
      formats: ['text', 'html', 'json'].map(format => sdk.formatEffectUncertainty(state, {format}))}));
  } else {
    throw new Error('InvalidEmbeddedStep');
  }
} finally {
  await client.close();
  if (server) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  await host?.close();
}
// The Host and execution owner live in this child; the parent waits for its exit.
process.exit(0);
