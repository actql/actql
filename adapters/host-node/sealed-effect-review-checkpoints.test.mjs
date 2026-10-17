// Actual Common projection, SQLite Checkpoint and encrypted Evidence Owners.
// The Preview preimage is independently authored test DATA, not a physical
// captured Program or an installed-package qualification.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey, openContinuationEvidence} from './local-continuation-evidence.mjs';
import {readContinuationLedgerBounded} from './bounded-continuation-metadata.mjs';
import {reviewBytesMatchCid, signedAnswer} from '../../packages/sdk/checkpoints.mjs';
import {vectors, canonicalText, hash, C, originalRun} from '../../scripts/fixtures/effect-review-projection-vectors.mjs';

const control=runtimeCore(moon).publicationControl;
const tuple={connection:'reference',resource:'records',operation:'effect'};
const pem=key=>key.export({type:key.type==='private'?'pkcs8':'spki',format:'pem'});
const clock=Date.parse('2026-10-18T00:00:00Z');
const policy=hash({version:'actql-remote-review-redaction/0.1',redacted:[]});
const limits={maxWireBytes:65536,maxNodes:10000,maxDepth:64};

function projector(vector){
  const original=checked(moon.strategyAdmitEffectComputationPreview(vector.previewWire,
    originalRun,vector.preview.authoring_context.authoring_context_cid,
    limits.maxWireBytes,limits.maxNodes,limits.maxDepth));
  return (policy,bounds)=>{
    const review=checked(moon.clientProgramProjectEffectReview(original,vector.previewWire,
      policy.authorityScopeCid,policy.approvalClaims,policy.redactionPolicyCid,
      bounds.maxWireBytes,bounds.maxNodes,bounds.maxDepth));
    return Object.freeze({identity:moon.strategyRunEvidenceIdentity(review),
      wire:moon.strategyRunEvidenceJson(review)});
  };
}

async function fixture(t){
  const root=await mkdtemp(join(tmpdir(),'actql-a-sealed-review-'));
  const reviewer=generateKeyPairSync('ed25519'),host=generateKeyPairSync('ed25519');
  const opened=new Set(),gates=new Set();
  const open=async()=>{
    const installed=await installRemoteCheckpoints({root,namespaceId:'local',authorityScopeCid:C('7'),
      ownerPrincipal:'owner',siteKey:'local',realizationKey:'source-free-values',environmentCid:C('4'),
      contractControl:control,now:()=>clock,authorization:{
        accountConfiguration:canonicalText({version:'actql-execution-account-config/0.1',account_id:'local',
          entries:[{entry_id:'write',outcome:'delegate',principal:{all:true},
            connection:{any_of:['reference']},resource:{any_of:['records']},
            operation:{any_of:['effect']},exclusions:[]}]}),resumeAfterAnswer:false,
        reviewers:[{keyId:'reviewer-key',reviewerId:'reviewer',principalId:'reviewer',publicKey:pem(reviewer.publicKey)}],
        reviewReaders:['reviewer'],hostKey:{keyId:'host-key',privateKey:pem(host.privateKey)}}});
    opened.add(installed);return installed;
  };
  const close=async installed=>{await installed.close();opened.delete(installed);};
  t.after(async()=>{
    for(const gate of gates)gate.close();
    for(const installed of opened)await close(installed);
    if(process.env.ACTQL_TEST_PRESERVE_SCRATCH==='1')t.diagnostic('Sealed review original custody retained: '+root);
    else await rm(root,{recursive:true,force:true});
  });
  const authorization=async(installed,vector,changed={})=>{
    const gate=await installed.effectAuthorization({runId:'review-run',runDefinitionCid:originalRun,
      unitId:'effect',declaredResults:['answer'],reviewWire:vector.previewWire,
      continuationWire:'{"request":"original"}',projectReview:projector(vector),
      async beforeDefer(){},...changed});gates.add(gate);return gate;
  };
  return {root,open,close,authorization,reviewer};
}

test('same original sealed Effect review survives encrypted storage and signed Checkpoint reopen',async t=>{
  const f=await fixture(t),vector=vectors.at(-1);
  let installed=await f.open();const gate=await f.authorization(installed,vector);
  const waiting=await gate.authorize('effect_commit',tuple,{subjectCid:vector.preview.effect_preview_cid});
  assert.equal(waiting.action,'waiting',JSON.stringify(waiting));
  const summary=(await installed.listCheckpoints({principalId:'reviewer',after:'',limit:10})).items[0];
  assert.ok(summary);assert.equal(summary.requiredArtifact.cid,vector.preview.effect_preview_cid);
  const expectedBody={...vector.body,redaction_policy_cid:policy};
  const expected={...expectedBody,review_projection_cid:hash(expectedBody)};
  assert.equal(summary.reviewProjectionCid,expected.review_projection_cid);
  gate.close();await f.close(installed);installed=await f.open();
  const view=installed.journal.inspect(summary.checkpointCid);
  assert.deepEqual(await installed.effectContinuation(view),{request:'original'});
  const review=await installed.reviewCheckpoint({principalId:'reviewer',checkpointCid:summary.checkpointCid,maxBytes:65536});
  const bytes=Buffer.from(review.contentBase64,'base64');
  assert.equal(bytes.toString('utf8'),canonicalText(expected));
  assert.equal(review.artifactCid,expected.review_projection_cid);
  assert.notEqual('sha256:'+createHash('sha256').update(bytes).digest('hex'),review.artifactCid);
  assert.equal(await reviewBytesMatchCid(bytes,review.artifactCid),true);
  await assert.rejects(installed.reviewCheckpoint({principalId:'foreign',checkpointCid:summary.checkpointCid,maxBytes:65536}),{code:'CheckpointReviewDenied'});
  await assert.rejects(installed.reviewCheckpoint({principalId:'reviewer',checkpointCid:summary.checkpointCid,maxBytes:bytes.length-1}),{code:'CheckpointReviewTooLarge'});
  const answer=await signedAnswer(summary,'approved',{keyId:'reviewer-key',reviewerId:'reviewer',
    authorityScopeCid:C('7'),sign:bytes=>sign(null,bytes,f.reviewer.privateKey)},new Date(clock).toISOString());
  const result=await installed.resolve({principalId:'reviewer',items:[answer]});
  assert.equal(result.results[0].status,'committed',JSON.stringify(result));
});

test('same review holding keeps byte and artifact identities separate through retirement',async t=>{
  const root=await mkdtemp(join(tmpdir(),'actql-a-review-holding-'));
  await createPrivateEvidenceKey(root);const key=await loadPrivateEvidenceKey(root);
  let ended=false,evidence;
  const open=()=>openContinuationEvidence({stateDirectory:root,...key,contractControl:control,
    preparation:()=>ended?{status:'ended'}:undefined,isTerminalRunOutcome:()=>false});
  evidence=open();t.after(async()=>{
    await evidence.close();
    if(process.env.ACTQL_TEST_PRESERVE_SCRATCH==='1')t.diagnostic('Original review holding retained: '+root);
    else await rm(root,{recursive:true,force:true});
  });
  const vector=vectors[0],item={name:'review_projection',wire:vector.reviewWire,artifactCid:vector.cid};
  const [storageCid]=await evidence.hold('same-original',originalRun,[item]);
  assert.notEqual(storageCid,vector.cid);
  const ledgerPath=join(root,'attempts/same-original.json');
  const metadata=await readFile(ledgerPath);
  const admitted=await readContinuationLedgerBounded(ledgerPath,'same-original',
    {maxWireBytes:metadata.length,maxLedgerEntries:1},undefined,control);
  assert.equal(admitted.holdings[0].artifact_cid,vector.cid);
  await assert.rejects(readContinuationLedgerBounded(ledgerPath,'same-original',
    {maxWireBytes:metadata.length,maxLedgerEntries:0},undefined,control),{code:'ContinuationLedgerEntriesLimit'});
  await assert.rejects(evidence.hold('same-original',originalRun,[{...item,artifactCid:C('9')}]),{code:'PrivateEvidenceConflict'});
  await assert.rejects(evidence.hold('same-original',originalRun,[{...item,name:'captured_input'}]),{code:'InvalidContinuationEvidence'});
  await evidence.close();evidence=open();const opened=await evidence.open('same-original');
  assert.equal(opened.requestCid,originalRun);
  assert.equal((await opened.artifactBytes('review_projection',vector.cid,{maxBytes:65536})).toString('utf8'),vector.reviewWire);
  assert.equal((await opened.bytes('review_projection',storageCid)).toString('utf8'),vector.reviewWire);
  await assert.rejects(opened.bytes('review_projection',vector.cid),{code:'ContinuationEvidenceNotHeld'});
  await assert.rejects(opened.artifactBytes('review_projection',C('9')),{code:'ContinuationEvidenceNotHeld'});
  ended=true;await evidence.settle();
  await assert.rejects(opened.artifactBytes('review_projection',vector.cid),{code:'ContinuationEvidenceRetired'});
});

test('copied and foreign Preview DATA cannot reach the Common projection issuer',()=>{
  let calls=0;
  const foreign=runtimeCore({...moon,clientProgramProjectEffectReview(){calls++;assert.fail('MustNotIssue');}}).publicationControl;
  const policy={authorityScopeCid:C('7'),approvalClaims:['effect_scope_approved'],redactionPolicyCid:C('8')};
  for(const candidate of [{},Object.freeze({kind:'effect-computation-preview'}),
    structuredClone(vectors[0].preview)]){
    assert.throws(()=>control.projectEffectComputationReview(candidate,policy,limits),/Foreign Effect computation Preview/);
    assert.throws(()=>foreign.projectEffectComputationReview(candidate,policy,limits),/Foreign Effect computation Preview/);
  }
  assert.equal(calls,0);
});

test('missing or foreign original projection refuses before a sealed Effect wait is persisted',async t=>{
  const f=await fixture(t),installed=await f.open(),vector=vectors[0];
  for(const projectReview of [undefined,projector(vectors[2]),()=>({identity:C('9'),wire:vector.reviewWire})]){
    const gate=await f.authorization(installed,vector,{projectReview});
    const result=await gate.authorize('effect_commit',tuple,{subjectCid:vector.preview.effect_preview_cid});
    assert.notEqual(result.action,'waiting',JSON.stringify(result));
    assert.notEqual(result.action,'dispatch',JSON.stringify(result));
    gate.close();
    assert.equal((await installed.listCheckpoints({principalId:'reviewer',after:'',limit:10})).items.length,0);
  }
});
