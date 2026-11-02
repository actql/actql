///|
// Actual parser/preparation and retained typed outcome with explicit buffer
// stop ports. No physical Host, epoch, Run admission or public ACK is supplied.
test "prepared typed refusal remains the same original instead of negative count inference" {
  let root = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 33554432L,
    retained_bytes: 33554432L,
    execution_bytes: 33554432L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let pool = @buffers.open_pool_on_ledger(root, 2097152L, 8, 1048576).unwrap()
  assert_eq(
    install_buffer_instance(
      5181L,
      root,
      capacity,
      None,
      pool,
      8,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(5181L).unwrap()
  let originals = @host.client_local_product_bootstrap_originals(
    "/typed-preparation-fixture", "2026-10-20T00:00:00.000Z",
  ).unwrap()
  let environment = @host.admit_client_check_environment(
    originals.environment,
    environment_body_cid(originals.environment),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let environment_bytes = @utf8.encode(originals.environment)
  let environment_slot = @buffers.reserve_output_buffer(
    pool,
    environment_bytes.length(),
    0L,
    () => true,
  ).unwrap()
  @buffers.supply_buffer_output(pool, environment_slot, environment_bytes).unwrap()
  let environment_borrow = @buffers.borrow_buffer(pool, environment_slot, () => {
    true
  }).unwrap()
  value.environments[1] = {
    borrow: environment_borrow,
    environment,
    wire: originals.environment,
    context: @preparation.bind_local_input_context(
      environment,
      [],
      "typed-original",
    ).unwrap(),
    publication: None,
  }
  let bytes = b"{\"input\":{\"format\":\"sql\",\"text\":\"SELECT (\"},\"kind\":\"aql\",\"parameters\":null}"
  let slot = @buffers.reserve_output_buffer(pool, bytes.length(), 0L, () => true).unwrap()
  @buffers.supply_buffer_output(pool, slot, bytes).unwrap()
  let borrow = @buffers.borrow_buffer(pool, slot, () => true).unwrap()
  let original : StoredPreparation = {
    borrow,
    slot,
    environment: 1,
    kind: 3,
    restoration: None,
    submitted: None,
    started: false,
    outcome: None,
    source: None,
    source_issue: None,
  }
  value.preparations[2] = original
  let before = prepared_outcome(5181L, 2)
  let prepared = prepare_program(5181L, 2)
  let status = prepared_outcome(5181L, 2)
  let original_issue = original.outcome
    is Some(Err(@preparation.Frontend(QuerySyntax(_))))
  let count = prepared_results(5181L, 2)
  let same = value.preparations.get(2) is Some(actual) &&
    physical_equal(actual, original)
  let foreign = prepared_outcome(5181L, 3)
  let closed = close_preparation(5181L, 2)
  let environment_closed = close_environment(5181L, 1)
  @buffers.close_buffer(pool, slot).unwrap()
  @buffers.close_buffer(pool, environment_slot).unwrap()
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  instance.val = None
  assert_eq(before, 0)
  assert_eq(prepared, 0)
  assert_eq(status, 2)
  assert_true(original_issue)
  assert_true(same)
  assert_eq(count, -22)
  assert_eq(foreign, -2)
  assert_eq(closed, 0)
  assert_eq(environment_closed, 0)
}
