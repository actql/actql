// Independent current-source/64-bit-ABI validator inputs, not Native captures.
// Decimal IDs below are synthetic labels, never observed addresses. Extents
// include the declared eight-byte allocation header. Pointer offsets are
// authored literals, not imported from the verifier's layout calculations.
// Source declarations: RelationChainExecutionState in selected_relation_provider,
// RelationChainInputPreparation and ProducerReadPreparation. Callback roles
// follow bounded_relation_chain_execution_state; their placement here exercises
// the validator and does not prove a compiler's capture-store order.
export function currentChainSyntheticFixture() {
  const record = (id, requestedBytes, captures) => ({id, requestedBytes,
    captures: captures.map(([offset, id]) => ({offset, id}))});
  const roots = {state:'102', used:'103', cancelled:'104', terminal:'105',
    reclaimed:'106', cleanupIndex:'107', sequence:'108', inputs:'109',
    execution:'110', measurement:'111', numeric:null, family:'112'};
  // The lifted environment has an Int between its third and fourth reference.
  const environment = record('120',80,[[0,'103'],[8,'112'],[16,null],
    [32,'111'],[40,'110'],[48,'102'],[56,'108']]);
  // Code pointers are not GC captures. The advance closure has an Int at 16,
  // seven references at 24..72, and its final Int at 80 (88 payload bytes).
  const callbacks = [
    record('121',96,[[8,'120'],[24,'105'],[32,'104'],[40,'103'],
      [48,'110'],[56,'109'],[64,'102'],[72,'108']]),
    record('122',40,[[8,'105'],[16,'104'],[24,'102']]),
    record('123',24,[[8,'105']]),
    record('124',48,[[8,'107'],[16,'106'],[24,'105'],[32,'102']]),
    record('125',24,[[8,'102']]),
  ];
  const cleanupContinuation=record('126',48,[[8,'102'],[16,'105'],[24,'106'],[32,'107']]);
  const owner=record('101',72,[[0,'121'],[8,'122'],[16,'123'],[24,'124'],
    [32,'127'],[40,'125'],[48,null],[56,'126']]);
  const state = (children, current, completed, preparation) => record('102',56,
    [[0,children],[8,current],[16,completed],[40,preparation]]);
  const initialChildren = {id:'200',backing:'201',length:1,slots:1,
    ownerBytes:24,backingBytes:16,staticBacking:false,elements:['204']};
  const initialCompleted = {id:'202',backing:'203',length:2,slots:2,
    ownerBytes:24,backingBytes:24,staticBacking:false,elements:[null,null],
    completions:[null,null]};
  const children = {...initialChildren,id:'210',backing:'211',elements:['214']};
  const completed = {...initialCompleted,elements:['215',null],completions:['216',null]};
  // Four cursor Ints occupy 56..68, matched/read occupy 72/80 and the
  // discriminant is at 88: 96 aligned payload bytes plus the allocation header.
  const preparation = record('230',104,[[0,'108'],[16,'109'],[24,'202'],
    [32,'231'],[40,'232'],[48,'233'],[72,null],[80,'240']]);
  const read = record('240',96,[[0,'241'],[8,'242'],[16,'243'],[64,'244'],[72,'245']]);
  const emptyChildren = {id:'251',backing:'250',length:0,slots:0,
    ownerBytes:24,backingBytes:8,staticBacking:true,elements:[]};
  const emptyCompleted = {...emptyChildren,id:'252',completions:[]};
  // Clone each observation separately: mutating one phase must not silently
  // mutate another phase's captures, arrays, preparation or cursor.
  const phase = (number, children, completed, preparation, read) => structuredClone({
    kind:'phase',phase:number,parent:'101',position:number===0?0:1,
    pending:number!==0,reclaiming:false,
    state:state(children.id,children.elements.at(-1)??null,completed.id,preparation?.id??null),
    owner,cleanupContinuation,callbacks,children,completed,preparation,read});
  return {role:'synthetic-current-source-abi; no Native execution or physical-lifetime evidence',
    records:[structuredClone({kind:'startup',parent:'101',count:2,maxValueBytes:10000,
      reclaimsScratch:true,roots,state:state('200','204','202',null),
      owner,cleanupContinuation,callbacks,environments:[environment]}),
    phase(0,initialChildren,initialCompleted,null,null),
    ...[1,2,3,4].map(n=>phase(n,children,completed,preparation,read)),
    ...[5,6].map(n=>phase(n,emptyChildren,emptyCompleted,null,null))]};
}
