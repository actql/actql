// Independent file-operation preimages: no product issuer, filesystem, Journal,
// schema generator or runtime observation supplies these expected identities.
import {physicalHash, canonicalText, hash, C, preview} from './effect-local-operation-vectors.mjs';
export {physicalHash, canonicalText, hash, C, preview};
const member = preview.preview.effects[0], row = member.changes[0];
export const directory='/original/e\u0301', name='accounts.json', resource='connector://mock/accounts';
export const selectorWire=canonicalText(row.target_row_identity);
export const installationCid=member.source_binding_cid;
export const targetBody={backend_kind:'json_file',installation_cid:installationCid,directory,name,
  resource,row_identity:JSON.parse(selectorWire)};
export const targetCid=hash(targetBody);
export const operation={effect_preview_cid:preview.preview.effect_preview_cid,
  effect_member_preview_cid:member.effect_member_preview_cid,row_preview_cid:row.row_preview_cid,
  installation_cid:installationCid,target_cid:targetCid,canonical_request_cid:C('3'),dispatch_entry_cid:C('4'),
  authorization_context_cid:member.authority_scope_cid,resolution_cid:C('6'),
  target_version_cid:row.target_guard.version_cid};
export const replacement=' {"items":[{"Id":3,"e\\u0301":"raw\\r\\n","é":null}],"keep":true}\n';
export const generation={device:'16777234',inode:'18446744073709551615',size:String(Buffer.byteLength(replacement))};
export const outcome={state:'applied',result:{Id:3,'e\u0301':'raw\r\n',é:null}};
export const body={version:'actql-local-effect-operation-receipt/0.1',backend_kind:'json_file',
  operation_kind:'update',replacement_status:'acknowledged',...operation,
  replacement_physical_sha256:physicalHash(replacement),replacement_byte_count:Buffer.byteLength(replacement),
  replacement_generation:generation,typed_outcome:outcome,typed_outcome_cid:hash(outcome)};
const seal=body=>({...body,receipt_cid:hash(body)});
export const receipt=seal(body),wire=canonicalText(receipt);
export const rowBody={version:'actql-effect-row-outcome-receipt/0.1',effect_preview_cid:operation.effect_preview_cid,
  effect_member_preview_cid:operation.effect_member_preview_cid,row_preview_cid:operation.row_preview_cid,
  dispatch_entry_cid:operation.dispatch_entry_cid,response_kind:'local_operation',
  local_operation_receipt_cid:receipt.receipt_cid,response_physical_sha256:physicalHash(wire),
  response_byte_count:Buffer.byteLength(wire),typed_outcome:outcome,typed_outcome_cid:hash(outcome)};
export const rowReceipt=seal(rowBody),rowWire=canonicalText(rowReceipt);
// Pins are authored from the literal preimages and Node crypto before Common executes.
export const expectedPins={targetCid:'sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb',receiptCid:'sha256:ae05fde44750b3abaabeb0d6b7aab96fa19a2f457fd8e19d2e15aad85796e1f1',rowCid:'sha256:004209abe4483c96be86096710fd8b3c9b99d862dc3a3820efd7778ff5a576f3'};
export const mutations=Object.keys(operation).map(field=>({name:'foreign '+field,
  wire:canonicalText(seal({...body,[field]:C('0')}))}));
for(const field of ['authorization_context_cid','resolution_cid','replacement_generation']){
  const changed={...body};delete changed[field];
  mutations.push({name:'missing '+field,wire:canonicalText(seal(changed))});
}
for(const [name,change] of [
  ['uncertain replacement',{replacement_status:'unknown'}],
  ['SQLite atomic substitution',{backend_kind:'sqlite',commit_status:'committed'}],
  ['HTTP substitution',{http_status_code:200,credential_use_cid:C('1')}],
  ['foreign physical digest',{replacement_physical_sha256:'0'.repeat(64)}],
  ['foreign byte count',{replacement_byte_count:body.replacement_byte_count+1}],
  ['foreign generation',{replacement_generation:{...generation,inode:'7'}}],
  ['noncanonical generation',{replacement_generation:{...generation,device:'01'}}],
  ['generation trailing newline',{replacement_generation:{...generation,device:'1\n'}}],
  ['generation overflow',{replacement_generation:{...generation,inode:'18446744073709551616'}}],
  ['unobserved outcome',{typed_outcome:{state:'unknown'}}],
  ['false typed identity',{typed_outcome_cid:C('0')}],
])mutations.push({name,wire:canonicalText(seal({...body,...change}))});
