// Independent expectations, never computed by a product codec or generator.
// Client–Host UTF-16 maxima/scalar minima: docs/reviews/2026-10-04-native-wire-contract.md.
// Numeric admission: docs/design/json-encoding.md; correlation: actql-client-host.json.
const q = JSON.stringify;
const cid = char => `sha256:${char.repeat(64)}`;
export const wireConnection = {mode:'remote', owner:'remote', consentRefs:[], runners:[]};
export const wireRef = {namespaceId:'namespace-a', authorityScopeCid:cid('a'), runDefinitionCid:cid('b')};
const profile = {version:'actql-client-host/0.1', mode:'remote', owner:'remote', durability:'durable', scopeRef:'principal-a', capabilities:['result-jsonl'], limits:{maxReadWireBytes:4096,maxRowWireBytes:1024,maxRowRetainedValueBytes:1024,maxRetainedValueBytes:4096,maxRows:10,maxBatchRows:3,maxBatchRetainedValueBytes:1024}};
const admission = {ref:wireRef, durability:'durable', revision:1};
const cancelRef = {...wireRef, cancelId:'cancel-a', expectedRevision:7};
const cancellation = {kind:'accepted',ref:wireRef,cancelRef,revision:8};
const held = {kind:'held', requestId:'original',prepareAttemptId:'prepare-a',state:'resuming',durability:'durable',lookupExpiresAt:'2026-10-04T10:00:00Z'};
const revision = 'rev:'+'1'.repeat(64);
// Explicit current pins copied from the registered owner, not resolved at test time.
const report = {version:'actql-check-outcome/0.1',reason_schema_cid:'sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511',outcome_schema_cid:'sha256:ce7df95dc9d069472f6dd61273acb6e5d09aba605347cddda5c4a23c6e5e52f6',outcome:'completed',report:{context_ref:'ctx:fixture',scope:{kind:'bound_input'},verdict:'invalid',runnable:{verdict:'no',reasons:[{code:'future_violation'}]},inputs:[{document_id:'source',revision,kind:'text',byte_length:10}],reasons:[{code:'future_violation',location:{kind:'text',document_id:'source',revision,start_byte:1,end_byte:5,precision:'exact'}}],requirements:[],coverage:{limits:[],unresolved:[]}}};
const vectors=[];
const add = (name,operation,value,expected,extra={}) => vectors.push({name,operation,valueJSON:q(value),expected,...extra});
const raw = (name,operation,valueJSON,expected,extra={}) => vectors.push({name,operation,valueJSON,expected,...extra});
for (const [label,number,expected] of [
 ['zero','0',true],['negative zero','-0',false],['negative decimal zero','-0.0',false],
 ['negative exponent zero','-0e0',false],['one','1',true],['integer decimal','1.0',true],
 ['fraction','1.5',false],['negative','-1',false],['safe maximum','9007199254740991',true],
 ['unsafe integer','9007199254740992',false],['huge integer','1'+'0'.repeat(400),false],
 ['true','true',false],['false','false',false],['null','null',false],['numeric string','"1"',false],
]) raw('admission revision '+label,'admission',`{"ref":${q(wireRef)},"durability":"durable","revision":${number}}`,expected);
add('admission missing revision','admission',{ref:wireRef,durability:'durable'},false);
for(const [label,text,expected] of [
 ['empty','',false],['ASCII255','a'.repeat(255),true],['ASCII256','a'.repeat(256),true],['ASCII257','a'.repeat(257),false],
 ['astral254','😀'.repeat(127),true],['astral256','😀'.repeat(128),true],['astral258','😀'.repeat(129),false],
 ['mixed256','a'+'😀'.repeat(127)+'b',true],['mixed257','aa'+'😀'.repeat(127)+'b',false],
 ['one astral','😀',true],['composed','é',true],['decomposed','e\u0301',true],['CRLF','a\r\nb',false],
 ['lone high surrogate','\ud800',false],['lone low surrogate','\udc00',false],['NUL','a\0b',false],['DEL','a\x7fb',false],
]) {
 add('profile scope '+label,'profile',{...profile,scopeRef:text},expected);
 add('Run namespace '+label,'run_ref',{...wireRef,namespaceId:text},expected);
}
// Whole-string non-control identifiers: independent registered-class vectors.
// A final LF is a control character, not an optional regex terminator. Keep
// separators/spaces and literal escape spellings distinct from decoded C0.
for (const point of [...Array.from({length:32}, (_, i) => i), 127]) {
 const character=String.fromCodePoint(point);
 for (const [position,text] of [['leading',character+'id'],['embedded','i'+character+'d'],['final','id'+character]])
  add('Run non-control U+'+point.toString(16).padStart(4,'0')+' '+position,'run_ref',{...wireRef,namespaceId:text},false);
}
for (const [label,text,expected] of [
 ['only LF','\n',false],['only CR','\r',false],['final CRLF','id\r\n',false],
 ['space',' ',true],['padded space',' id ',true],['line separator','\u2028',true],
 ['final line separator','id\u2028',true],['paragraph separator','\u2029',true],
 ['final paragraph separator','id\u2029',true],['literal escape','\\n',true],
 ['literal Unicode escape','\\u000a',true],['NEL','\u0085',true],['astral','😀',true],
]) {
 add('Run non-control '+label,'run_ref',{...wireRef,namespaceId:text},expected);
 add('profile non-control '+label,'profile',{...profile,scopeRef:text},expected);
}
for(const [label,value,expected] of [['missing',undefined,true],['null',null,false],['valid','reason',true]]) {
 const valueHeld={...held,state:'ended',endReason:'cancelled'};
 if(value!==undefined)valueHeld.terminalErrorCode=value;
 add('held optional field '+label,'held',valueHeld,expected,{requestId:'original'});
}
add('held valid','held',held,true,{requestId:'original'});
add('held wrong identity','held',held,false,{requestId:'foreign'});
add('held unknown variant','held',{...held,state:'running'},false,{requestId:'original'});
add('held extra field','held',{...held,foreign:true},false,{requestId:'original'});
for(const [label,id,expected] of [['valid','original',true],['empty','',false],['null',null,false],['boolean',true,false],['257','a'.repeat(257),false],['astral256','😀'.repeat(128),true],['astral258','😀'.repeat(129),false]]) {
 add('lookup not-found expected '+label,'lookup',{kind:'not_found'},expected,{requestId:id});
 add('lookup Unknown expected '+label,'lookup',{kind:'unknown',reason:'query_failed'},expected,{requestId:id});
}
const found={kind:'found',requestId:'original',ref:wireRef,durability:'durable',lookupExpiresAt:'2026-10-04T10:00:00Z'};
add('lookup found matching','lookup',found,true,{requestId:'original'});
add('lookup found foreign','lookup',found,false,{requestId:'foreign'});
add('lookup unknown discriminant','lookup',{kind:'future'},false,{requestId:'original'});
add('lookup no Unicode normalization','lookup',{...found,requestId:'é'},false,{requestId:'e\u0301'});
for(const [label,value,expected] of [
 ['valid',cancellation,true],['stale revision',{...cancellation,revision:6},false],
 ['accepted unchanged revision',{...cancellation,revision:7},false],
 ['already requested unchanged revision',{...cancellation,kind:'already_requested',revision:7},true],
 ['wrong Run',{...cancellation,ref:{...wireRef,runDefinitionCid:cid('c')}},false],
 ['unknown kind',{...cancellation,kind:'future'},false],
 ['old protocol version',{...cancellation,version:'actql-cancellation/0.0'},false],
]) add('cancellation '+label,'cancellation',value,expected,{expectedJSON:q(cancelRef)});
for(const [label,reference] of [['authority',{...cancelRef,authorityScopeCid:cid('c')}],['namespace',{...cancelRef,namespaceId:'foreign'}],['cancel ID',{...cancelRef,cancelId:'foreign'}],['expected revision',{...cancelRef,expectedRevision:6}]])
 add('cancellation foreign expected '+label,'cancellation',cancellation,false,{expectedJSON:q(reference)});
add('report valid','check_outcome',report,true);
for(const [label,mutate] of [
 ['old outcome CID',value=>{value.outcome_schema_cid='sha256:2cb5ef23a94213780dc377fa9260b9fcfde1e9f7341063bd37cd7a7676aab10f';}],
 ['foreign outcome CID',value=>{value.outcome_schema_cid=cid('0');}],
 ['foreign reason CID',value=>{value.reason_schema_cid=cid('0');}],
 ['old version',value=>{value.version='actql-check-outcome/0.0';}],
 ['foreign input revision',value=>{value.report.reasons[0].location.revision='rev:'+'2'.repeat(64);}],
 ['outside input',value=>{value.report.reasons[0].location.end_byte=11;}],
 ['reversed range',value=>{value.report.reasons[0].location.start_byte=6;}],
 ['duplicate input',value=>{value.report.inputs.push({...value.report.inputs[0]});}],
 ['unknown variant',value=>{value.outcome='future';}],
 ['NULL location',value=>{value.report.reasons[0].location=null;}],
]) {const value=structuredClone(report);mutate(value);add('report '+label,'check_outcome',value,false);}
const missingLocation=structuredClone(report);delete missingLocation.report.reasons[0].location;
add('report omitted optional location','check_outcome',missingLocation,true);
// Nested public requirement admission uses the canonical value-contract Owner.
// The name grammar uses ECMAScript whitespace, not Python re.ASCII whitespace.
for (const [label,name,expected] of [
 ['plain','field',true],['empty','',false],['ASCII space',' ',false],['NBSP','\u00a0',false],
 ['Ogham space','\u1680',false],['em space','\u2003',false],['line separator','\u2028',false],
 ['BOM','\ufeff',false],['NEL is not JS whitespace','\u0085',true],
 ['Mongolian separator is not JS whitespace','\u180e',true],['zero width space','\u200b',true],
 ['composed','é',true],['decomposed','e\u0301',true],['reserved','__cid',false],['dot','a.b',false],
]) {
 const value=structuredClone(report);
 value.report.verdict='verified';value.report.runnable={verdict:'no',reasons:[{code:'parameter_value_required'}]};value.report.scope={kind:'template_only'};value.report.reasons=[];
 value.report.requirements=[{code:'parameter_value_required',facts:{parameter:'object',expected_type:'object',admission:{
  kind:'parameter_declaration',contract_schema_cid:'sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1',
  contract:{type:'object',nullable:false,additional_properties:false,fields:{[name]:{type:'string',nullable:false}}},
  constraints:[],supplier:'caller',
 }}}];
 add('report canonical field '+label,'check_outcome',value,expected);
 if(label==='plain') for(const [field,number] of [['nullable',0],['additional_properties',0]]) {
  const changed=structuredClone(value);changed.report.requirements[0].facts.admission.contract[field]=number;
  add('report boolean '+field+' rejects numeric zero','check_outcome',changed,false);
 }
}
export const publicWireLanguageVectors=Object.freeze(vectors);
