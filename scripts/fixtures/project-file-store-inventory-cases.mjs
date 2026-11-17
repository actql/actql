// Authored ordinary Project File STORE cases for the matching installed
// supplier. No Core, private Host, fake Reference, grant or effect receipt is
// constructed here. The ordinary owner must approve, execute and publish each
// case, close once, and cold-attach the SAME Saved Run without resubmitting.
const connection='destination';
const store={target_ref:`connector://${connection}/files`,
  mapping_ref:`mapping:${connection}.local.files.store.v1`};

export function projectFileStoreRows101() {
  const expected=Array.from({length:101},(_,index)=>({
    path:`input-${String(index).padStart(3,'0')}.jsonl`,
    body:JSON.stringify({id:index,token:`payload-${(index*37)%101}`})+'\n'}));
  // Creation order deliberately differs from key order. Every key also owns
  // distinct literal bytes, so zipping independently ordered inventories fails.
  const inputs=Array.from({length:101},(_,index)=>expected[(index*57)%101]);
  return Object.freeze({name:'project-file-store-101rows-one-definition',format:'sql',
    source:'SELECT f.path AS path, f.size_bytes AS size_bytes, c.content AS content '+
      'FROM LIST_FILES(source) AS f '+
      'JOIN source.contents AS c ON f.resource = c.resource AND f.version = c.version '+
      '|> RESULT answer '+
      '|> EFFECT STORE destination.files SET (path = path, content = content)',
    inputs:Object.freeze(inputs.map(Object.freeze)),
    expectedWrites:101,expectedDefinitions:1,resultName:'answer',
    expectedProjection:Object.freeze(expected.map(({path,body})=>Object.freeze({path,size_bytes:Buffer.byteLength(body)}))),
    expectedFiles:Object.freeze(expected.map(Object.freeze))});
}

export function projectFileStoreMembers17() {
  const body='{"id":1}\n';
  const files=Array.from({length:17},(_,index)=>({path:`member-${String(index).padStart(2,'0')}.jsonl`,body}));
  const effects=Object.fromEntries(files.map((_,index)=>[
    `save${String(index).padStart(2,'0')}`,{command:{from:{result:'content'},
      target:{published_store:{...store}},contract:`command:${connection}.local.files.store.v1`,
      input:{path:{literal:files[(index*5)%17].path},content:{field:'content'}}}}]));
  const program={version:'actql/0.1',id:'project-file-store-17definitions-one-row',
    stages:[{id:'source',inputs:{},steps:[
      {values:{schema:{id:{type:'number',nullable:false}},rows:[{id:1}]},as:'seed'},
      {serialize:{format:'jsonl',fields:['id'],name:'one.jsonl',preserve_order:true,
        bounds:{max_rows:1,max_bytes:32}},as:'attachment'}],
      results:{content:{from:'attachment',fields:['name','content','media_type','size_bytes','row_count']}},effects}],
    results:{answer:{from:{stage:'source',result:'content'}}}};
  return Object.freeze({name:program.id,format:'json',source:JSON.stringify(program),
    inputs:Object.freeze([]),expectedWrites:17,expectedDefinitions:17,resultName:'answer',
    expectedProjection:Object.freeze([Object.freeze({name:'one.jsonl',size_bytes:Buffer.byteLength(body),row_count:1})]),
    expectedFiles:Object.freeze(files.map(Object.freeze))});
}

export const projectFileStoreInventoryAcceptance=Object.freeze({
  // Keep the existing Project Local connector declarations and original
  // operator Account. `source` and `destination` are actual distinct roots;
  // destination.files is one installed Local STORE owner in both cases.
  installation:'ordinary Project Local files/contents and required STORE approval',
  budgetBytes:512*1024**2,
  // Functional acquisition/Compute headroom, shared by every installed platform.
  // This does not select an execution budget or a latency acceptance criterion.
  captureTimeoutMs:90_000,
  capture:['one fresh Run per case','actual public checkpoint and sealed review; no writes',
    'FIRST close returns before original Program and Source suppliers are removed'],
  approve:['different process; cold attach SAME original Run and Checkpoint',
    'original Program and Source suppliers absent before signed approval',
    'zero Source or Model starts; exact original Effect commit count',
    'all expected files equal independent literal bytes','all row receipts typed success; exact expected commit count',
    'full named Result retained before FIRST close','FIRST close returns and original scoped descriptors drain'],
  saved:['separate process; same installed package cohort, Account and original Run ref',
    'original input files absent','full Saved Result equal capture','all destination bytes and physical generations unchanged',
    'zero new commits, Source/Model reexecution or submissions','FIRST close returns and scoped descriptors drain'],
  refusal:['insufficient original budget before construction','foreign original/Run/Task/generation',
    'changed current before write','explicit tighter row/member policy','failed cleanup retains original child until real ACK'],
});
