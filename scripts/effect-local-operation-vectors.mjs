import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {vectors,preview,operation,installationCid,targetCid,configurationWire,
  selectorWire,resource,expectedPins,mutations,C,canonicalText} from './fixtures/effect-local-operation-vectors.mjs';
import {authoring,originalRun} from './fixtures/effect-review-projection-vectors.mjs';

export function generateEffectLocalOperationVectors(){
  assert.deepEqual({installationCid,targetCid,receipts:vectors.map(v=>v.receipt.receipt_cid),
    rows:vectors.map(v=>v.rowReceipt.receipt_cid)},expectedPins);
  const q=JSON.stringify;
  const bounds='20000, 2000, 32';
  const original=`  let original = admit_effect_preview_identity(${q(preview.previewWire)}, ${q(originalRun)}, ${q(authoring.authoring_context_cid)}, ${bounds}).unwrap()\n`;
  const op=`  let operation = prepare_effect_local_operation(original, 0, 0, ${[installationCid,targetCid,operation.canonical_request_cid,operation.dispatch_entry_cid,operation.authorization_use_cid,operation.approval_use_cid,operation.target_version_cid].map(q).join(', ')}).unwrap()\n`;
  let source='// Generated from independent local-operation transaction receipt preimages.\n';
  for(const v of vectors){
    const result=v.status==='committed'?`Applied(${q(v.observed)})`:`Conflict(${v.observed===null?'None':`Some(${q(v.observed)})`})`;
    source+=`\n///|\ntest "local operation original: ${v.name}" {\n${original}${op}`+
      `  let response = prepare_effect_local_operation_receipt(operation, ${result}, ${q(canonicalText(v.outcome))}, ${bounds}).unwrap()\n`+
      `  assert_eq(effect_local_operation_receipt_wire(response), ${q(v.wire)})\n`+
      `  assert_eq(effect_local_operation_receipt_cid(response), ${q(v.receipt.receipt_cid)})\n`+
      `  let admitted = admit_effect_local_operation_receipt(operation, ${q(v.wire)}, ${bounds}).unwrap()\n`+
      `  let row = issue_effect_row_outcome_receipt_from_local(original, 0, 0, ${q(operation.dispatch_entry_cid)}, admitted, ${bounds}).unwrap()\n`+
      `  assert_eq(publication_contract_json(row), ${q(v.rowWire)})\n`+
      `  assert_eq(publication_contract_identity(row), ${q(v.rowReceipt.receipt_cid)})\n`+
      `  assert_true(admit_effect_row_outcome_receipt_from_local(original, 0, 0, ${q(operation.dispatch_entry_cid)}, admitted, ${q(v.rowWire)}, ${bounds}) is Ok(_))\n}\n`;
  }
  source+=`\n///|\ntest "local operation original refuses foreign and missing saved bindings" {\n${original}${op}`+
    mutations.map(m=>`  // ${m.name}\n  assert_true(admit_effect_local_operation_receipt(operation, ${q(m.wire)}, ${bounds}) is Err(_))\n`).join('')+'}\n';
  source+=`\n///|\ntest "local operation original preserves exact installation and target bytes" {\n`+
    `  assert_eq(effect_local_installation_cid(${q(configurationWire)}, ${bounds}).unwrap(), ${q(installationCid)})\n`+
    `  assert_eq(effect_local_target_cid(${q(installationCid)}, ${q(resource)}, ${q(selectorWire)}, ${bounds}).unwrap(), ${q(targetCid)})\n`+
    `  assert_true(effect_local_installation_cid(${q(configurationWire)}, 1, 2000, 32) is Err(_))\n`+
    `  assert_true(effect_local_target_cid(${q(installationCid)}, ${q(resource)}, ${q(selectorWire)}, 1, 2000, 32) is Err(_))\n`+
    `  assert_true(effect_local_target_cid(${q(installationCid)}, ${q(resource)}, ${q(' '+selectorWire)}, ${bounds}) is Err(_))\n}\n`;
  source+=`\n///|\ntest "local operation original refuses wrong row version and nonterminal evidence" {\n${original}${op}`+
    `  assert_true(prepare_effect_local_operation(original, 0, 0, ${[installationCid,targetCid,operation.canonical_request_cid,operation.dispatch_entry_cid,operation.authorization_use_cid,operation.approval_use_cid,C('0')].map(q).join(', ')}) is Err(ForeignRow))\n`+
    `  assert_true(prepare_effect_local_operation_receipt(operation, Applied(${q(C('9'))}), ${q('{"state":"applied","result":{},"action":"updated"}')}, ${bounds}) is Err(_))\n`+
    `  assert_true(prepare_effect_local_operation_receipt(operation, Conflict(None), ${q('{"state":"unknown"}')}, ${bounds}) is Err(_))\n`+
    `  assert_true(prepare_effect_local_operation_receipt(operation, Applied(${q(C('9'))}), ${q(canonicalText(vectors[0].outcome))}, 1, 2000, 32) is Err(_))\n`+
    `  let response = admit_effect_local_operation_receipt(operation, ${q(vectors[0].wire)}, ${bounds}).unwrap()\n`+
    `  assert_true(issue_effect_row_outcome_receipt_from_local(original, 0, 0, ${q(C('0'))}, response, ${bounds}) is Err(_))\n`+
    `  assert_true(admit_effect_row_outcome_receipt_from_local(original, 0, 0, ${q(operation.dispatch_entry_cid)}, response, ${q(vectors[1].rowWire)}, ${bounds}) is Err(_))\n}\n`;
  return execFileSync(process.env.MOON_HOME+'/bin/moonfmt',['-'],{input:source,encoding:'utf8'});
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const path='src/run_publication/effect_local_operation.generated_wbtest.mbt';
  const source=generateEffectLocalOperationVectors();
  if(process.argv.includes('--write'))writeFileSync(path,source);
  else assert.equal(readFileSync(path,'utf8'),source,'Stale independent local-operation receipt vectors');
}
