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
  for
    (sql, code, classification) in [
      ("SELECT (", "ClientProgramInvalidInput", "invalid_input"),
      (
        "SELECT STRING_AGG('one', '|') AS labels", "ClientProgramAggregateOrderRequired",
        "invalid_input",
      ),
      (
        "WITH r AS (SELECT 1 AS k, 2 AS v UNION ALL SELECT 2, 3) SELECT ARRAY_AGG(v ORDER BY k) AS items FROM r",
        "ClientProgramOrderUnresolved", "operation_failed",
      ),
    ] {
    let bytes = @utf8.encode(
      "{\"input\":{\"format\":\"sql\",\"text\":\"" +
      sql +
      "\"},\"kind\":\"aql\",\"parameters\":null}",
    )
    let slot = @buffers.reserve_output_buffer(pool, bytes.length(), 0L, () => {
      true
    }).unwrap()
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
      project_request: None,
    }
    value.preparations[2] = original
    assert_eq(prepared_outcome(5181L, 2), 0)
    assert_eq(prepare_program(5181L, 2), 0)
    assert_eq(prepared_outcome(5181L, 2), 2)
    if classification == "invalid_input" {
      assert_true(
        original.outcome is Some(Err(@preparation.Frontend(QuerySyntax(_)))),
      )
    }
    assert_eq(
      preparation_failure_problem(original),
      Some((code, classification)),
    )
    assert_eq(prepared_results(5181L, 2), -22)
    assert_true(
      value.preparations.get(2) is Some(actual) &&
      physical_equal(actual, original),
    )
    assert_eq(close_preparation(5181L, 2), 0)
    @buffers.close_buffer(pool, slot).unwrap()
  }
  let foreign = prepared_outcome(5181L, 3)
  let environment_closed = close_environment(5181L, 1)
  @buffers.close_buffer(pool, environment_slot).unwrap()
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  instance.val = None
  assert_eq(foreign, -2)
  assert_eq(environment_closed, 0)
}
