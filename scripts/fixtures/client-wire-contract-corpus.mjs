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
