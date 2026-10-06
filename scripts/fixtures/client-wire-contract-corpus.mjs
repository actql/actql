// Independently authored contract expectations. Never import a validator or
// generator to calculate these answers.
export const connection = {mode:'remote', owner:'remote', consentRefs:[], runners:[]};
export const ref = {namespaceId:'namespace-a', authorityScopeCid:`sha256:${'a'.repeat(64)}`, runDefinitionCid:`sha256:${'b'.repeat(64)}`};
export const profile = {version:'actql-client-host/0.1', mode:'remote', owner:'remote', durability:'durable', scopeRef:'principal-a', capabilities:['result-jsonl'], limits:{maxReadWireBytes:4096,maxRowWireBytes:1024,maxRowRetainedValueBytes:1024,maxRetainedValueBytes:4096,maxRows:10,maxBatchRows:3,maxBatchRetainedValueBytes:1024}};
export const admission = {ref, durability:'durable', revision:1};
const corpus=[];
const add=(name,kind,value,expected,selected=connection)=>corpus.push({name,kind,value,expected,selected});
const omit=(value,key)=>Object.fromEntries(Object.entries(value).filter(([k])=>k!==key));
for(const [kind,base] of [['profile',profile],['admission',admission],['run_ref',ref],['connection',connection]]) {
 add(`${kind}:valid`,kind,base,true);
 add(`${kind}:unknown field`,kind,{...base,extra:true},false);
 for(const key of Object.keys(base)) add(`${kind}:missing ${key}`,kind,omit(base,key),false);
 add(`${kind}:null`,kind,null,false);
}
for(const [label,text,expected] of [['empty','',false],['newline','a\nb',false],['nul','a\0b',false],['delete','a\x7fb',false],['255','a'.repeat(255),true],['256','a'.repeat(256),true],['257','a'.repeat(257),false],['astral256','😀'.repeat(128),true],['astral258','😀'.repeat(129),false]]) {
 add(`profile:scope ${label}`,'profile',{...profile,scopeRef:text},expected);
 add(`reference:namespace ${label}`,'run_ref',{...ref,namespaceId:text},expected);
 add(`admission:namespace ${label}`,'admission',{...admission,ref:{...ref,namespaceId:text}},expected);
}
for(const value of [0,-1,1.5,9007199254740992]) add(`profile:invalid limit ${value}`,'profile',{...profile,limits:{...profile.limits,maxRows:value}},false);
add('profile:safe integer limit','profile',{...profile,limits:{...profile.limits,maxRows:9007199254740991}},true);
add('profile:extra limit','profile',{...profile,limits:{...profile.limits,extra:1}},false);
add('profile:capability control','profile',{...profile,capabilities:['a\nb']},false);
add('profile:duplicate capability remains accepted','profile',{...profile,capabilities:['a','a']},true);
for(const value of [-1,0.5,9007199254740992]) add(`admission:invalid revision ${value}`,'admission',{...admission,revision:value},false);
add('admission:zero revision','admission',{...admission,revision:0},true);
add('admission:extra reference','admission',{...admission,ref:{...ref,extra:true}},false);
for(const kind of ['profile','admission']) {
 const base=kind==='profile'?profile:admission;
 add(`${kind}:required durable downgrade`,kind,{...base,durability:'volatile'},false,{...connection,durability:'durable'});
 add(`${kind}:volatile request permits durable`,kind,base,true,{...connection,durability:'volatile'});
}
add('profile:mode mismatch','profile',{...profile,mode:'local'},false);
add('profile:owner mismatch','profile',{...profile,owner:'local'},false);
add('connection:owner disagreement','connection',{...connection,owner:'local'},false);
add('connection:remote runner','connection',{...connection,runners:['runner']},false);
add('connection:remote movement','connection',{...connection,movementPolicyRef:'policy'},false);
add('connection:remote cloud','connection',{...connection,cloudConnectionRef:'cloud'},false);
add('connection:duplicate consent','connection',{...connection,consentRefs:['a','a']},false);
const hybrid={...connection,mode:'hybrid',owner:'local',movementPolicyRef:'policy',cloudConnectionRef:'cloud'};
add('connection:hybrid local','connection',hybrid,true);
add('connection:hybrid local missing cloud','connection',omit(hybrid,'cloudConnectionRef'),false);
add('connection:hybrid missing movement','connection',omit(hybrid,'movementPolicyRef'),false);
const cloud={...omit(hybrid,'cloudConnectionRef'),owner:'cloud',runners:['runner']};
add('connection:hybrid cloud','connection',cloud,true);
add('connection:hybrid cloud no runner','connection',{...cloud,runners:[]},false);
add('connection:hybrid cloud unexpected cloud ref','connection',{...cloud,cloudConnectionRef:'cloud'},false);
for (const mode of ['remote','local','hybrid']) for (const owner of ['remote','local','cloud']) {
 const value = mode === 'hybrid' ? {...hybrid,owner} : {...connection,mode,owner};
 add(`connection:mode-owner ${mode}/${owner}`, 'connection', value,
   mode === 'remote' ? owner === 'remote' : mode === 'local' ? owner === 'local' : owner === 'local');
}
for (const text of ['bad', `sha256:${'A'.repeat(64)}`, `sha256:${'a'.repeat(63)}`, `sha256:${'a'.repeat(65)}`, `sha256:${'a'.repeat(64)}\n`]) {
 add(`reference:invalid CID ${JSON.stringify(text)}`, 'run_ref', {...ref, authorityScopeCid:text}, false);
}
add('connection:both forbidden options','connection',{...connection,movementPolicyRef:'p',cloudConnectionRef:'c'},false);
add('admission:attach durable downgrade','admission',{...admission,durability:'volatile'},false,{...connection,durability:'durable'});
corpus.at(-1).operation = 'attach';
export const clientWireCorpus=corpus;

// These outcomes are authored from the public contract, not from validator or
// generator output. Length boundaries count UTF-16 units, including astral text.
const fixedRequestId = 'fixed-request';
const lookupFound = {kind: 'found', requestId: fixedRequestId, ref,
  durability: 'durable', lookupExpiresAt: '2026-10-04T10:00:00Z'};
const lookupUnknown = {kind: 'unknown', reason: 'query_failed'};
const heldCheckpoint = {checkpointId: 'checkpoint-a',
  checkpointCid: `sha256:${'d'.repeat(64)}`, kind: 'run_scope',
  expiresAt: '2026-10-04T10:00:00Z'};
const held = {kind: 'held', requestId: fixedRequestId,
  prepareAttemptId: 'prepare-a', state: 'waiting_checkpoint',
  durability: 'durable', lookupExpiresAt: '2026-10-04T10:00:00Z',
  checkpoint: heldCheckpoint};
const boundedTextCases = [
  ['empty', '', false],
  ['newline', 'a\nb', false],
  ['nul', 'a\0b', false],
  ['delete', 'a\x7fb', false],
  ['255', 'a'.repeat(255), true],
  ['256', 'a'.repeat(256), true],
  ['257', 'a'.repeat(257), false],
  ['astral256', '😀'.repeat(128), true],
  ['astral258', '😀'.repeat(129), false],
];
function addLookup(name, value, expected, requestId = fixedRequestId) {
  corpus.push({name: `lookup:${name}`, kind: 'lookup', value, expected,
    selected: connection, requestId, operation: 'lookup-request',
    failureCode: 'InvalidHostRequestLookup'});
}
function addHeld(name, value, expected, requestId = fixedRequestId) {
  // Both public routes must make the same held-response admission decision.
  for (const [route, operation, failureCode] of [
    ['lookup', 'lookup-request', 'InvalidHostRequestLookup'],
    ['submit', 'start', 'SubmissionUnknown'],
  ]) {
    corpus.push({name: `held:${route}:${name}`, kind: 'held', value,
      expected, selected: connection, requestId, operation, failureCode});
  }
}

for (const [label, value] of [
  ['not_found', {kind: 'not_found'}],
  ['unknown', lookupUnknown],
  ['found', lookupFound],
]) {
  addLookup(`${label} valid`, value, true);
  addLookup(`${label} unknown field`, {...value, extra: true}, false);
  for (const key of Object.keys(value)) {
    addLookup(`${label} missing ${key}`, omit(value, key), false);
  }
}
for (const [label, value] of [
  ['null', null], ['array', []], ['string', 'found'], ['boolean', true],
]) addLookup(`invalid root ${label}`, value, false);
addLookup('found requestId mismatch',
  {...lookupFound, requestId: 'another-request'}, false);
addLookup('found volatile remains accepted',
  {...lookupFound, durability: 'volatile'}, true);
addLookup('found invalid durability',
  {...lookupFound, durability: 'unknown'}, false);
for (const [label, text, expected] of boundedTextCases) {
  addLookup(`unknown reason ${label}`, {...lookupUnknown, reason: text},
    expected);
  addLookup(`found lookupExpiresAt ${label}`,
    {...lookupFound, lookupExpiresAt: text}, expected);
  // NUL and empty IDs are response values only. NUL cannot be an OS argument;
  // the CLI rejects an empty required option before reaching the endpoint.
  addLookup(`found requestId ${label}`, {...lookupFound, requestId: text},
    expected, expected ? text : fixedRequestId);
}
for (const [label, value] of [
  ['null', null], ['number', 1], ['boolean', true], ['object', {}], ['array', []],
]) {
  addLookup(`unknown reason type ${label}`, {...lookupUnknown, reason: value},
    false);
  addLookup(`found lookupExpiresAt type ${label}`,
    {...lookupFound, lookupExpiresAt: value}, false);
}
// These invalid expected IDs can reach the Native endpoint. Rejection must be
// InvalidHostRequestLookup after the response, never a parser or spawn failure.
for (const [label, requestId, expected] of [
  ['newline', 'a\nb', false],
  ['delete', 'a\x7fb', false],
  ['257', 'a'.repeat(257), false],
  ['256', 'a'.repeat(256), true],
  ['astral256', '😀'.repeat(128), true],
  ['astral258', '😀'.repeat(129), false],
]) {
  for (const [kind, value] of [
    ['not_found', {kind: 'not_found'}],
    ['unknown', lookupUnknown],
    ['found', {...lookupFound, requestId}],
  ]) addLookup(`expected requestId ${label} with ${kind}`, value, expected,
    requestId);
}

// Explicit state/presence truth table. Columns are state, checkpoint,
// endReason, terminalErrorCode, and acceptance. In particular, resuming may
// retain a checkpoint; ended may retain a checkpoint and terminalErrorCode.
const heldPresenceTruthTable = [
  ['waiting_checkpoint', false, false, false, false],
  ['waiting_checkpoint', false, false, true, false],
  ['waiting_checkpoint', false, true, false, false],
  ['waiting_checkpoint', false, true, true, false],
  ['waiting_checkpoint', true, false, false, true],
  ['waiting_checkpoint', true, false, true, false],
  ['waiting_checkpoint', true, true, false, false],
  ['waiting_checkpoint', true, true, true, false],
  ['resuming', false, false, false, true],
  ['resuming', false, false, true, false],
  ['resuming', false, true, false, false],
  ['resuming', false, true, true, false],
  ['resuming', true, false, false, true],
  ['resuming', true, false, true, false],
  ['resuming', true, true, false, false],
  ['resuming', true, true, true, false],
  ['ended', false, false, false, false],
  ['ended', false, false, true, false],
  ['ended', false, true, false, true],
  ['ended', false, true, true, true],
  ['ended', true, false, false, false],
  ['ended', true, false, true, false],
  ['ended', true, true, false, true],
  ['ended', true, true, true, true],
];
for (const [state, checkpoint, endReason, terminalErrorCode, expected]
  of heldPresenceTruthTable) {
  const value = {...omit(held, 'checkpoint'), state};
  if (checkpoint) value.checkpoint = heldCheckpoint;
  if (endReason) value.endReason = 'cancelled';
  if (terminalErrorCode) value.terminalErrorCode = 'ClientRunStartDenied';
  addHeld(`presence ${state} C${+checkpoint}E${+endReason}T${+terminalErrorCode}`,
    value, expected);
}
addHeld('valid control', held, true);
addHeld('unknown field', {...held, extra: true}, false);
addHeld('fabricated RunRef', {...held, ref}, false);
addHeld('requestId mismatch', {...held, requestId: 'another-request'}, false);
addHeld('invalid state', {...held, state: 'running'}, false);
addHeld('volatile durability', {...held, durability: 'volatile'}, false);
for (const key of ['kind', 'requestId', 'prepareAttemptId', 'state',
  'durability', 'lookupExpiresAt']) {
  addHeld(`missing ${key}`, omit(held, key), false);
}
for (const [label, value] of [
  ['null', null], ['array', []], ['string', 'held'], ['boolean', true],
]) addHeld(`invalid root ${label}`, value, false);
for (const key of ['requestId', 'prepareAttemptId', 'lookupExpiresAt',
  'endReason', 'terminalErrorCode', 'checkpointId', 'expiresAt']) {
  for (const [label, text, expected] of boundedTextCases) {
    let value;
    if (key === 'checkpointId' || key === 'expiresAt') {
      value = {...held, checkpoint: {...heldCheckpoint, [key]: text}};
    } else if (key === 'endReason' || key === 'terminalErrorCode') {
      value = {...held, state: 'ended', endReason: 'cancelled', [key]: text};
    } else {
      value = {...held, [key]: text};
    }
    addHeld(`${key} ${label}`, value, expected,
      key === 'requestId' && expected ? text : fixedRequestId);
  }
}
for (const [label, value] of [
  ['null', null], ['number', 1], ['boolean', true], ['object', {}], ['array', []],
]) {
  for (const key of ['requestId', 'prepareAttemptId', 'lookupExpiresAt']) {
    addHeld(`${key} type ${label}`, {...held, [key]: value}, false);
  }
  for (const key of ['endReason', 'terminalErrorCode']) {
    addHeld(`${key} type ${label}`,
      {...held, state: 'ended', endReason: 'cancelled', [key]: value}, false);
  }
  for (const key of ['checkpointId', 'expiresAt', 'checkpointCid', 'kind']) {
    addHeld(`checkpoint ${key} type ${label}`,
      {...held, checkpoint: {...heldCheckpoint, [key]: value}}, false);
  }
  addHeld(`checkpoint type ${label}`, {...held, checkpoint: value}, false);
}
addHeld('checkpoint unknown field',
  {...held, checkpoint: {...heldCheckpoint, extra: true}}, false);
for (const key of Object.keys(heldCheckpoint)) {
  addHeld(`checkpoint missing ${key}`,
    {...held, checkpoint: omit(heldCheckpoint, key)}, false);
}
for (const kind of ['run_scope', 'read_access', 'data_egress', 'cost_scope',
  'effect_set']) {
  addHeld(`checkpoint kind ${kind}`,
    {...held, checkpoint: {...heldCheckpoint, kind}}, true);
}
addHeld('checkpoint kind unknown',
  {...held, checkpoint: {...heldCheckpoint, kind: 'future_kind'}}, false);
for (const [label, checkpointCid] of [
  ['empty', ''], ['prefix', `SHA256:${'d'.repeat(64)}`],
  ['uppercase', `sha256:${'D'.repeat(64)}`],
  ['short', `sha256:${'d'.repeat(63)}`],
  ['long', `sha256:${'d'.repeat(65)}`],
  ['nonhex', `sha256:${'g'.repeat(64)}`],
  ['newline', `sha256:${'d'.repeat(64)}\n`],
  ['nul', `sha256:${'d'.repeat(64)}\0`],
]) {
  addHeld(`checkpoint CID ${label}`,
    {...held, checkpoint: {...heldCheckpoint, checkpointCid}}, false);
}
