// Independently authored transaction-receipt preimages. No product issuer,
// schema generator, backend, runtime or physical observation is imported.
import {createHash} from 'node:crypto';
import {canonicalText, hash, C, vectors as reviews} from './effect-review-projection-vectors.mjs';
export {canonicalText, hash, C};
export const preview = reviews[0];
export const configurationWire = '{"installation":"local-original","mapping":"mapping:accounts","note":"e\\u0301","primary_identity":"Id"}';
export const physicalHash = text => createHash('sha256').update(text).digest('hex');
export const installationCid = `sha256:${physicalHash(configurationWire)}`;
export const selectorWire = canonicalText(preview.preview.effects[0].changes[0].target_row_identity);
export const resource = 'connector://mock/accounts';
export const targetBody = {backend_kind:'sqlite', installation_cid:installationCid,
  resource, row_identity:JSON.parse(selectorWire)};
export const targetCid = hash(targetBody);
export const operation = {effect_preview_cid:preview.preview.effect_preview_cid,
  effect_member_preview_cid:preview.preview.effects[0].effect_member_preview_cid,
  row_preview_cid:preview.preview.effects[0].changes[0].row_preview_cid,
  backend_kind:'sqlite',installation_cid:installationCid,target_cid:targetCid,
  canonical_request_cid:C('3'),dispatch_entry_cid:C('4'),
  authorization_use_cid:C('5'),approval_use_cid:C('6'),target_version_cid:C('a')};
const seal = body => ({...body,receipt_cid:hash(body)});
function vector(name,status,observed,outcome) {
  const body = {version:'actql-local-effect-operation-receipt/0.1',...operation,
    operation_kind:'update',commit_status:status,observed_version_cid:observed,
    typed_outcome:outcome,typed_outcome_cid:hash(outcome)};
  const receipt=seal(body),wire=canonicalText(receipt);
  const rowBody={version:'actql-effect-row-outcome-receipt/0.1',
    effect_preview_cid:operation.effect_preview_cid,
    effect_member_preview_cid:operation.effect_member_preview_cid,
    row_preview_cid:operation.row_preview_cid,dispatch_entry_cid:operation.dispatch_entry_cid,
    response_kind:'local_operation',local_operation_receipt_cid:receipt.receipt_cid,
    response_physical_sha256:physicalHash(wire),response_byte_count:Buffer.byteLength(wire),
    typed_outcome:outcome,typed_outcome_cid:hash(outcome)};
  const rowReceipt=seal(rowBody);
  return {name,status,observed,outcome,body,receipt,wire,rowBody,rowReceipt,rowWire:canonicalText(rowReceipt)};
}
export const vectors=[
  vector('committed update','committed',C('9'),{state:'applied',result:{Id:3,'e\u0301':'raw\r\n',é:null}}),
  vector('version conflict','conflict',C('8'),{state:'failed',error:{code:'conflict',message:'Target changed'}}),
  vector('absent target conflict','conflict',null,{state:'failed',error:{code:'conflict',message:'Target absent'}}),
];
// Fixed before executing Common, from these literal preimages and Node crypto.
export const expectedPins = {
  "installationCid": "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
  "targetCid": "sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410",
  "receipts": [
    "sha256:6a15bf1bb1067842019b3949c090d3d517d836fe69ae70449a6898e2d59d90db",
    "sha256:8f2a48ea8f36dcf452f7cb8d9ff8d824c96f2e408db5d31504d6be0d4319577e",
    "sha256:456c4689e173635fadcd606b91ef8f80dc7b0378626e41173450eb67c2505a03"
  ],
  "rows": [
    "sha256:d48eab82606665bc1618d2408a5f4c37acbbec42ae43ff8d8ce50c47c24ba395",
    "sha256:ad71b010b2b3021d5812f3997537fd4e89bca0c1beb82562e583110485634107",
    "sha256:820f5182641a258d89eb743942ad7fb897c39e0c6fdee444bb4c68594d3b4080"
  ]
};
export const foreignFields=Object.keys(operation);
export const mutations=foreignFields.map(field=>{
  const body={...vectors[0].body,[field]:field==='backend_kind'?'http':C('0')};
  return {name:`foreign ${field}`,wire:canonicalText(seal(body))};
});
for(const field of ['authorization_use_cid','approval_use_cid','dispatch_entry_cid']){
  const body={...vectors[0].body};delete body[field];
  mutations.push({name:`missing ${field}`,wire:canonicalText(seal(body))});
}
for(const [name,change] of [
  ['HTTP substitution',{http_status_code:200,credential_use_cid:C('1')}],
  ['uncertain COMMIT',{commit_status:'unknown'}],
  ['false outcome CID',{typed_outcome_cid:C('0')}],
  ['applied without version',{observed_version_cid:null}],
  ['unmatched conflict',{typed_outcome:{state:'failed',error:{code:'denied',message:'Not a conflict'}}}],
]) {
  mutations.push({name,wire:canonicalText(seal({...vectors[0].body,...change}))});
}
