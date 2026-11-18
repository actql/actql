///|
// These FFI values are only primitive geometry DATA and a JSON footprint.
// No opaque Core value, capacity, Resource, permission or tuple is fabricated.
extern "js" fn mock_file_footprint_geometry(
  rows : Int,
  bytes : Int,
) -> FixedArray[Int64] =
  #|(rows,bytes) => {
  #|  const load=process.getBuiltinModule('node:module').createRequire(process.cwd()+'/package.json');
  #|  const {declaredProjectMockFootprintConstructionGeometry:geometry}=load('./adapters/host-node/declared-project-catalog-construction.mjs');
  #|  const q=geometry([{physical:{itemsPath:['salesforce','会社😀','rows'],keyPath:['salesforce','会社😀','key'],primaryIdentity:'id'}}],rows,bytes);
  #|  return [q.workspace.nodes,q.workspace.text,q.workspace.wire];
  #|}

///|
extern "js" fn mock_file_footprint_produce(rows : Int, bytes : Int) -> String =
  #|(rows,bytes) => {
  #|  const load=process.getBuiltinModule('node:module').createRequire(process.cwd()+'/package.json');
  #|  const {mockFileRowFootprint:produce}=load('./adapters/local-node/installed-mock-row-effect.mjs');
  #|  const selectors=Array.from({length:rows},(_,i)=>i===0?'x'.repeat(Math.max(0,bytes-256)):'same-'+i);
  #|  return JSON.stringify(produce({bindingCid:'sha256:'+'a'.repeat(64),target:{write:{resource:'会社😀'},physical:{itemsPath:['salesforce','会社😀','rows'],keyPath:['salesforce','会社😀','key'],primaryIdentity:'id'}},selectors}));
  #|}

///|
test "Mock exact footprint actual JS recipe fits the exact shared reservation" {
  for bytes in [4096, 1048576] {
    let geometry = mock_file_footprint_geometry(100, bytes)
    let quote = installed_source_construction_capacity(
      0L,
      0L,
      0L,
      geometry[0],
      geometry[1],
      geometry[2],
    ).unwrap()
    let retained = @execution.execution_capacity_retained_bytes(quote)
    let execution = @execution.execution_capacity_execution_bytes(quote)
    assert_eq(retained, 0L)
    assert_true(execution > 0L)
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: retained,
      execution_bytes: execution,
    }).unwrap()
    let reservation = @resources.reserve_capacity(ledger, retained, execution).unwrap()
    // Execute the SAME imported production projector only after the original
    // shared Ledger admits its complete callback construction envelope.
    let footprint = mock_file_footprint_produce(100, bytes)
    assert_true(footprint.contains("\"kind\":\"exact_targets\""))
    assert_true(footprint.contains("会社😀"))
    @resources.settle_capacity(ledger, reservation).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
}

///|
test "Mock exact footprint one-short shared reservation refuses before production" {
  let geometry = mock_file_footprint_geometry(100, 1048576)
  let quote = installed_source_construction_capacity(
    0L,
    0L,
    0L,
    geometry[0],
    geometry[1],
    geometry[2],
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: retained,
    execution_bytes: execution - 1L,
  }).unwrap()
  let before = @resources.ledger_usage(ledger)
  let mut entered = false
  match @resources.reserve_capacity(ledger, retained, execution) {
    Ok(_) => {
      entered = true
      mock_file_footprint_produce(100, 1048576) |> ignore
    }
    Err(issue) => assert_true(issue is @resources.ExecutionLimit)
  }
  assert_false(entered)
  assert_eq(@resources.ledger_usage(ledger), before)
}
