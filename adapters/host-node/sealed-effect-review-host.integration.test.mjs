// Real Common/SQLite/encrypted Store/HTTPS Client boundaries with the existing
// stateful loopback Salesforce fixture. No live service or packed cohort.
import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {approveHeldSet,expectedUpdates,readComputeEffectInstallation,waitFor} from
  '../connectors/salesforce/test/read-compute-effect.fixture.mjs';

test('public Effect review keeps sealed original row evidence through approval and same Run recovery',async t=>{
  const setup=await readComputeEffectInstallation(t);
  const observations={},diagnostics=[];
  t.after(async()=>{
    const facts={observations,diagnostics:diagnostics.map(({name,detail})=>({name,code:detail?.code,cause:detail?.cause?.code})),
      queries:setup.queries(),writes:setup.writes().length};
    if(process.env.ACTQL_TEST_PRESERVE_SCRATCH==='1'){
      const path=join(setup.root,'sealed-review-authorized-observations.json');
      await writeFile(path,JSON.stringify(facts)+'\n',{mode:0o600});t.diagnostic('Authorized review observations retained: '+path);
    }
  });
  let host=await setup.openHost({diagnostics});const owner=await host.as('owner-token');
  const submissionRef=await setup.persistSubmission(owner.newSubmission({nonce:'sealed-original-review'}));
  const execution=await owner.startSource(setup.program(),{format:'json',submissionRef});
  const ref=execution.ref;
  const waiting=await waitFor(async()=>{const state=await execution.status();return state.status==='waiting_checkpoint'?state:undefined;});
  observations.waiting=waiting;
  assert.equal(setup.queries(),1);assert.equal(setup.writes().length,0);
  const reviewer=await host.as('reviewer-token');
  const [checkpoint]=(await reviewer.checkpoints()).items;
  assert.ok(checkpoint);assert.equal(checkpoint.kind,'effect_set');
  const response=await reviewer.reviewCheckpoint(checkpoint,{maxBytes:65536});
  const review=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(response.bytes));
  assert.equal(review.version,'actql-review-projection/0.1');
  assert.deepEqual(Object.keys(review).sort(),['version','review_projection_cid','effect_preview_cid',
    'authority_scope_cid','approval_claims','authoring_context_cid','redaction_policy_cid',
    'sensitivity','retention_class','encryption_required','displayed_scope','displayed_permissions',
    'displayed_rows','displayed_authoring_context'].sort());
  assert.equal(response.artifactCid,checkpoint.reviewProjectionCid);
  assert.equal(review.review_projection_cid,checkpoint.reviewProjectionCid);
  assert.equal(review.effect_preview_cid,checkpoint.requiredArtifact.cid);
  assert.equal(review.authority_scope_cid,ref.authorityScopeCid);
  assert.deepEqual(review.approval_claims,checkpoint.requirements);
  assert.equal(review.sensitivity,'restricted');assert.equal(review.retention_class,'approval-evidence');
  assert.equal(review.encryption_required,true);
  assert.deepEqual(review.displayed_scope.effects.map(({kind,count})=>({kind,count})),[{kind:'update',count:2}]);
  assert.ok(review.displayed_permissions.length>0);
  assert.equal(review.displayed_authoring_context.length,1);
  assert.equal(review.displayed_authoring_context[0].authoring_context_cid,review.authoring_context_cid);
  assert.equal(review.displayed_rows.length,2);
  assert.deepEqual(review.displayed_rows.map(row=>row.after.value.Name).sort(),['key-1-processed','key-3-processed']);
  for(const row of review.displayed_rows){
    assert.equal(row.effect_id,'save');assert.match(row.row_preview_cid,/^sha256:[0-9a-f]{64}$/u);
    assert.equal(row.after.state,'present');assert.equal(row.target_guard.state,'version');
    assert.match(row.target_guard.version_cid,/^sha256:[0-9a-f]{64}$/u);
    assert.equal(row.intended_changes.state,'present');
    assert.equal(row.intended_changes.value.Name,row.after.value.Name);
    if(row.preview_strength==='full_diff'){
      assert.equal(row.before.state,'present');assert.ok(['record-1','record-3'].includes(row.before.value.Name));
    }else{
      assert.equal(row.preview_strength,'targeted');assert.deepEqual(row.before,{state:'unavailable'});
    }
  }
  await host.close();host=await setup.openHost({diagnostics});
  const reopenedReviewer=await host.as('reviewer-token');
  const recovered=await reopenedReviewer.reviewCheckpoint(checkpoint,{maxBytes:65536});
  assert.deepEqual(recovered.bytes,response.bytes);
  const reopenedOwner=await host.as('owner-token'),same=await reopenedOwner.attach(ref);
  assert.equal((await same.status()).run_id,waiting.run_id);
  assert.equal((await approveHeldSet(host,same)).checkpointCid,checkpoint.checkpointCid);
  observations.approved=await same.status();
  // The existing fixture explicitly selects resumeAfterAnswer:false. Its
  // confirmed durable answer is resumed by the next Host, not by this client.
  await host.close();host=await setup.openHost({diagnostics});
  const resumed=await (await host.as('owner-token')).attach(ref);
  const terminal=await waitFor(async()=>{const state=await resumed.status();observations.last=state;return ['succeeded','failed','needs_reconciliation'].includes(state.status)?state:undefined;});
  assert.equal(terminal.status,'succeeded',JSON.stringify(terminal));assert.equal(terminal.run_id,waiting.run_id);
  assert.deepEqual(await resumed.result('updates').all(),expectedUpdates);
  assert.equal(setup.queries(),1);assert.equal(setup.writes().length,2);
  await host.close();
});
