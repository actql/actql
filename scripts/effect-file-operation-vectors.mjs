import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {expectedPins,targetCid,receipt,rowReceipt,preview,operation,directory,name,resource,
  selectorWire,replacement,generation,outcome,wire,rowWire,mutations,canonicalText,C} from './fixtures/effect-file-operation-vectors.mjs';
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
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const path='src/run_publication/effect_file_operation.generated_wbtest.mbt',source=generateEffectFileOperationVectors();
  if(process.argv.includes('--write'))writeFileSync(path,source);
  else assert.equal(readFileSync(path,'utf8'),source,'Stale independent file-operation receipt vectors');
}
