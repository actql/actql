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

// Independent two-row semantic preimage. Raw changes are CID ordered while
// execution row_order is reversed; never use one index space for the other.
export const reorderedPreview=(()=>{
  const p=structuredClone(preview.preview), member=p.effects[0], first=member.changes[0];
  const rows=['A','B'].map((id,i)=>{
    const row={...structuredClone(first),target_row_identity:id,row_idempotency_key:C(i?'5':'4'),
      target_guard:{state:'version',version_cid:C(i?'b':'a')},
      before:{state:'present',value:{id,value:1}},after:{state:'present',value:{id,value:2}},
      intended_changes:{state:'present',value:{value:2}}};
    row.row_preview_cid=hash({version:'actql-effect-preview-row/0.1',
      program_definition_cid:p.program_definition_cid,invocation_cid:p.invocation_cid,
      effect_identity_cid:member.effect_identity_cid,resolved_contract_cid:member.resolved_mapping_contract_cid,
      operation:member.effect_kind,target_row_identity:row.target_row_identity,
      preview_strength:member.preview_strength,target_guard:row.target_guard,
      intended_changes:row.intended_changes,before:row.before,after:row.after});
    return row;
  }).sort((a,b)=>a.row_preview_cid < b.row_preview_cid ? -1 : a.row_preview_cid > b.row_preview_cid ? 1 : 0);
  member.changes=rows;member.row_order=rows.map(r=>r.row_preview_cid).reverse();member.count=2;member.max_items=2;
  const {effect_member_preview_cid:ignored,...m}=member;void ignored;
  m.changes=rows.map(({row_idempotency_key:excluded,...r})=>{void excluded;return r;});
  member.effect_member_preview_cid=hash({version:'actql-effect-member-preview/0.1',member:m});
  const {effect_preview_cid:old,run_identity_cid:run,authoring_context:context,...semantic}=p;void old;void run;void context;
  semantic.effects=[{...m,effect_member_preview_cid:member.effect_member_preview_cid}];
  p.effect_preview_cid=hash(semantic);
  return p;
})();
export const reorderedPreviewWire=canonicalText(reorderedPreview);
export const reorderedRawA=reorderedPreview.effects[0].changes[0];
export const reorderedRawB=reorderedPreview.effects[0].changes[1];
export const reorderedExpectedPins={preview:'sha256:852e6a4986a8522861a48db32e78de8cb704dcac25c89f3ad29c8fd6a56e6558',rawA:'sha256:0426447180fcebf4aa8c57983b23050b177e74be6eabf33d1bdf07408cab5a50',rawB:'sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac'};
