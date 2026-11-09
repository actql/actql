import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {expectedPins,targetCid,receipt,rowReceipt,preview,operation,directory,name,resource,
  selectorWire,replacement,generation,outcome,body,rowBody,wire,rowWire,mutations,canonicalText,C,
  reorderedPreview,reorderedPreviewWire,reorderedRawA,reorderedRawB,reorderedExpectedPins,hash,physicalHash} from './fixtures/effect-file-operation-vectors.mjs';
import {authoring,originalRun} from './fixtures/effect-review-projection-vectors.mjs';
export function generateEffectFileOperationVectors(){
  assert.deepEqual({targetCid,receiptCid:receipt.receipt_cid,rowCid:rowReceipt.receipt_cid},expectedPins);
  const q=JSON.stringify,b='20000, 2000, 32';
  const original=`  let original = admit_effect_preview_identity(${q(preview.previewWire)}, ${q(originalRun)}, ${q(authoring.authoring_context_cid)}, ${b}).unwrap()\n`;
  const op=`  let operation = prepare_effect_file_operation(original, 0, 0, ${[operation.installation_cid,targetCid,operation.canonical_request_cid,operation.dispatch_entry_cid,operation.authorization_context_cid,operation.resolution_cid,operation.target_version_cid].map(q).join(', ') }).unwrap()\n`;
  const evidence=`  let evidence = admit_effect_file_replacement_evidence(@utf8.encode(${q(replacement)}), ${q(generation.device)}, ${q(generation.inode)}, ${generation.size}L, 4096).unwrap()\n`;
  let s='// Generated from independent original file-operation preimages, never product output.\n';
  s+=`\n///|\ntest "file operation original binds exact physical bytes and generation" {\n${original}${op}${evidence}`+
    `  assert_eq(effect_file_target_cid(${q(operation.installation_cid)}, ${q(directory)}, ${q(name)}, ${q(resource)}, ${q(selectorWire)}, ${b}).unwrap(), ${q(targetCid)})\n`+
    `  let response = prepare_effect_file_operation_receipt(operation, evidence, ${q(canonicalText(outcome))}, ${b}).unwrap()\n`+
    `  assert_eq(effect_file_operation_receipt_wire(response), ${q(wire)})\n`+
    `  assert_eq(effect_file_operation_receipt_cid(response), ${q(receipt.receipt_cid)})\n`+
    `  let admitted = admit_effect_file_operation_receipt(operation, evidence, ${q(wire)}, ${b}).unwrap()\n`+
    `  let row = issue_effect_row_outcome_receipt_from_file(original, 0, 0, ${q(operation.dispatch_entry_cid)}, admitted, ${b}).unwrap()\n`+
    `  assert_eq(publication_contract_json(row), ${q(rowWire)})\n`+
    `  assert_eq(publication_contract_identity(row), ${q(rowReceipt.receipt_cid)})\n`+
    `  assert_true(admit_effect_row_outcome_receipt_from_file(original, 0, 0, ${q(operation.dispatch_entry_cid)}, admitted, ${q(rowWire)}, ${b}) is Ok(_))\n}\n`;
  s+=`\n///|\ntest "file operation original refuses foreign uncertain and HTTP evidence" {\n${original}${op}${evidence}`+
    mutations.map(m=>`  // ${m.name}\n  assert_true(admit_effect_file_operation_receipt(operation, evidence, ${q(m.wire)}, ${b}) is Err(_))\n`).join('')+'}\n';
  s+=`\n///|\ntest "file operation evidence refuses noncanonical generation sizes and unobserved outcomes" {\n${original}${op}${evidence}`+
    ['','01','-1','1\n','18446744073709551616'].map(v=>`  assert_true(admit_effect_file_replacement_evidence(@utf8.encode(${q(replacement)}), ${q(v)}, ${q(generation.inode)}, ${generation.size}L, 4096) is Err(_))\n`).join('')+
    `  assert_true(admit_effect_file_replacement_evidence(@utf8.encode(${q(replacement)}), ${q(generation.device)}, ${q(generation.inode)}, 0L, 4096) is Err(_))\n`+
    `  assert_true(admit_effect_file_replacement_evidence(@utf8.encode(${q(replacement)}), ${q(generation.device)}, ${q(generation.inode)}, ${generation.size}L, 1) is Err(_))\n`+
    `  assert_true(prepare_effect_file_operation_receipt(operation, evidence, ${q('{"state":"unknown"}')}, ${b}) is Err(_))\n`+
    `  assert_true(prepare_effect_file_operation_receipt(operation, evidence, ${q('{"action":"updated","result":{},"state":"applied"}')}, ${b}) is Err(_))\n`+
    `  let response = prepare_effect_file_operation_receipt(operation, evidence, ${q(canonicalText(outcome))}, ${b}).unwrap()\n`+
    `  assert_true(issue_effect_row_outcome_receipt_from_file(original, 0, 0, ${q(C('0'))}, response, ${b}) is Err(_))\n}\n`;
  return execFileSync(process.env.MOON_HOME+'/bin/moonfmt',['-'],{input:s,encoding:'utf8'});
}
export function generateEffectFileLedgerVectors(){
  assert.deepEqual({preview:reorderedPreview.effect_preview_cid,rawA:reorderedRawA.row_preview_cid,
    rawB:reorderedRawB.row_preview_cid},reorderedExpectedPins);
  const q=JSON.stringify,b='20000, 512, 32',m=reorderedPreview.effects[0];
  const fixture=`fn file_ordered_receipt_fixture() -> (@publication.EffectPreviewIdentity, EffectRecoveryBinding, EffectLedgerBasis, EffectLedgerEntry, EffectLedgerEntry) raise {
`+
    `  let scope = prepare_logical_request_scope(${q(operation.authorization_context_cid)}, "ordered-file-request", 256).unwrap()
`+
    `  let wire = ${q(reorderedPreviewWire)}
`+
    `  let initial = @publication.admit_effect_preview_identity(wire, ${q(originalRun)}, ${q(authoring.authoring_context_cid)}, ${b}).unwrap()
`+
    `  let raw_a = prepare_effect_dispatch_key(scope, @publication.effect_preview_semantic_identity(initial), ${q(canonicalText(reorderedRawA.target_row_identity))}, 256, 32, 8).unwrap()
`+
    `  let raw_b = prepare_effect_dispatch_key(scope, @publication.effect_preview_semantic_identity(initial), ${q(canonicalText(reorderedRawB.target_row_identity))}, 256, 32, 8).unwrap()
`+
    `  let completed = @publication.complete_effect_preview_dispatch_keys(wire, [[raw_a.cid,raw_b.cid]], ${q(originalRun)}, ${q(authoring.authoring_context_cid)}, ${b}).unwrap()
`+
    `  let preview = admit_effect_preview_apply_identity(completed, ${q(originalRun)}, ${q(authoring.authoring_context_cid)}, scope, [[raw_a,raw_b]], ${b}).unwrap()
`+
    `  assert_eq(@publication.effect_preview_ordered_row_identity(preview,0,0), Some(${q(reorderedRawB.row_preview_cid)}))
`+
    `  let binding = prepare_effect_recovery_bindings(preview, scope, "file-program", "file-node", 2, 3).unwrap()[0][0]
`+
    `  let basis = prepare_effect_ledger_basis(scope, binding.locator, binding.key, ${[C('a'),m.effect_member_preview_cid,reorderedRawB.row_preview_cid,C('3'),C('5'),'unavailable',C('8'),C('9')].map(q).join(',')}).unwrap()
`+
    `  let prepared = issue_prepared_effect_ledger_entry(basis, ${b}).unwrap()
`+
    `  let dispatch = issue_next_effect_ledger_entry(prepared,"dispatching",None,${b}).unwrap()
`+
    `  (preview,binding,basis,prepared,dispatch)
}
`;
  const evidence=`  let evidence = @publication.admit_effect_file_replacement_evidence(@utf8.encode(${q(replacement)}),${q(generation.device)},${q(generation.inode)},${generation.size}L,4096).unwrap()
`;
  const aOutcome={state:'applied',result:{row:'raw-A'}};
  const aBody={...body,effect_preview_cid:reorderedPreview.effect_preview_cid,
    effect_member_preview_cid:m.effect_member_preview_cid,row_preview_cid:reorderedRawA.row_preview_cid,
    dispatch_entry_cid:'@DISPATCH@',target_version_cid:reorderedRawA.target_guard.version_cid,
    typed_outcome:aOutcome,typed_outcome_cid:hash(aOutcome)};
  const aRow={...rowBody,effect_preview_cid:reorderedPreview.effect_preview_cid,
    effect_member_preview_cid:m.effect_member_preview_cid,row_preview_cid:reorderedRawA.row_preview_cid,
    dispatch_entry_cid:'@DISPATCH@',local_operation_receipt_cid:'@LOCAL@',response_physical_sha256:'@SHA@',
    response_byte_count:'@LENGTH@',typed_outcome:aOutcome,typed_outcome_cid:hash(aOutcome)};
  let s='// Generated independent two-row reordered final-reducer controls. No physical IO or authority is claimed.\n\n///|\n'+fixture;
  s+=`\n///|\ntest "file ordered final reducer refuses another raw row at this ordinal" {
`+
    `  let (preview,binding,basis,prepared,dispatch) = file_ordered_receipt_fixture()
`+
    `  let metadata = @publication.seal_publication_contract("effect_local_operation_receipt",${q(canonicalText(aBody))}.replace_all(old="@DISPATCH@",new=dispatch.cid),${b}).unwrap()
`+
    `  let local_wire = @publication.publication_contract_json(metadata)
`+
    `  let saved = @publication.admit_saved_effect_file_operation_receipt(local_wire,@utf8.encode(${q(replacement)}),4096,${b}).unwrap()
`+
    `  let row_body = ${q(canonicalText(aRow))}.replace_all(old="@DISPATCH@",new=dispatch.cid).replace_all(old="@LOCAL@",new=@publication.publication_contract_identity(metadata)).replace_all(old="@SHA@",new=@sha.hex(@utf8.encode(local_wire))).replace_all(old=${q(JSON.stringify("@LENGTH@"))},new=@utf8.encode(local_wire).length().to_string())
`+
    `  let row = @publication.seal_publication_contract("effect_row_outcome_receipt",row_body,${b}).unwrap()
`+
    `  let committed = issue_effect_row_receipt_terminal_entry_from_file(preview,0,0,binding.scope,binding.locator,binding.key,basis.canonical_request_cid,dispatch,[prepared,dispatch],dispatch.cid,saved,@publication.publication_contract_json(row),${b})
  @debug.debug_inspect(committed.map(entry => effect_ledger_entry_state_code(entry)),content="Err(ForeignReceipt)")
}
`;
  s+=`\n///|\ntest "file ordered final reducer settles only the matching ordered row" {
`+
    `  let (preview,binding,basis,prepared,dispatch) = file_ordered_receipt_fixture()
${evidence}`+
    `  let operation = @publication.prepare_effect_file_operation(preview,0,0,${q(operation.installation_cid)},${q(targetCid)},basis.canonical_request_cid,dispatch.cid,${q(operation.authorization_context_cid)},${q(operation.resolution_cid)},${q(reorderedRawB.target_guard.version_cid)}).unwrap()
`+
    `  assert_eq(operation.row_preview_cid,${q(reorderedRawB.row_preview_cid)})
`+
    `  let saved = @publication.prepare_effect_file_operation_receipt(operation,evidence,${q(canonicalText(outcome))},${b}).unwrap()
`+
    `  let row = @publication.issue_effect_row_outcome_receipt_from_file(preview,0,0,dispatch.cid,saved,${b}).unwrap()
`+
    `  let terminal = issue_effect_row_receipt_terminal_entry_from_file(preview,0,0,binding.scope,binding.locator,binding.key,basis.canonical_request_cid,dispatch,[prepared,dispatch],dispatch.cid,saved,@publication.publication_contract_json(row),${b}).unwrap()
`+
    `  assert_eq(effect_ledger_entry_state_code(terminal),2)
`+
    `  assert_eq(terminal.logical_item_locator_cid,binding.locator.cid)
`+
    `  assert_true(issue_effect_row_receipt_terminal_entry_from_file(preview,0,1,binding.scope,binding.locator,binding.key,basis.canonical_request_cid,dispatch,[prepared,dispatch],dispatch.cid,saved,@publication.publication_contract_json(row),${b}) is Err(_))
}
`;
  return execFileSync(process.env.MOON_HOME+'/bin/moonfmt',['-'],{input:s,encoding:'utf8'});
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  for(const [path,source] of [
    ['src/run_publication/effect_file_operation.generated_wbtest.mbt',generateEffectFileOperationVectors()],
    ['src/effect_application/file_outcome_receipt.generated_wbtest.mbt',generateEffectFileLedgerVectors()],
  ])if(process.argv.includes('--write'))writeFileSync(path,source);
    else assert.equal(readFileSync(path,'utf8'),source,'Stale independent file-operation receipt vectors: '+path);
}
