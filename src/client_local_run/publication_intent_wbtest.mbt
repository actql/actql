///|
fn publication_intent_fixture(
  plan : LocalRunPlan,
  max_results? : Int = 2,
  max_wire_bytes? : Int = 100000,
) -> Result[LocalPublicationIntent, LocalPublicationIntentIssue] {
  prepare_local_publication_intent(
    plan,
    "local-results",
    "sha256:" + "3".repeat(64),
    "sha256:" + "4".repeat(64),
    "2026-10-10T00:00:00.000Z",
    "original-attempt",
    "sha256:" + "5".repeat(64),
    None,
    "2026-10-10T00:00:01.000Z",
    { max_results, max_wire_bytes, max_nodes: 10000, max_depth: 100, },
  )
}

///|
let intent_program : String =
  #|{"version":"actql/0.1","id":"python.local.intent","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["n"]}}}],"results":{"é/~😀":{"from":{"stage":"main","result":"rows"}},"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
test "Local publication intent fixes all original checked Result occurrences before Compute" {
  let plan = plan(
    prepared(@input.Program(intent_program)),
    "original-intent-run",
  )
  let host = compute_host(plan)
  let run = local_compute_run(host)
  let first = @strategy.next_captured_task(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let intent = publication_intent_fixture(plan).unwrap()
  let inventory = local_publication_intent_inventory(intent)
  assert_eq(@publication.checked_publication_inventory_count(inventory), 2)
  assert_eq(intent.definitions.length(), 2)
  let names = [0, 1].map(index => {
    @publication.checked_publication_inventory_name(inventory, index).unwrap()
  })
  // The independently authored names and their exact spelling survive the
  // checked inventory. Both aliases select one original producer occurrence.
  assert_true(names.contains("answer") && names.contains("é/~😀"))
  assert_eq(
    @publication.checked_publication_inventory_task(inventory, 0).unwrap(),
    @publication.checked_publication_inventory_task(inventory, 1).unwrap(),
  )
  let (request, attempt) = local_publication_intent_contracts(intent)
  let wire = @publication.publication_contract_json(request)
  assert_true(wire.contains("\"result_name\":\"answer\""))
  assert_true(wire.contains("\"result_name\":\"é/~😀\""))
  assert_true(
    wire.contains("\"authority_scope_cid\":\"sha256:" + "b".repeat(64) + "\""),
  )
  assert_true(
    wire.contains(
      "\"run_definition_cid\":\"" + local_run_definition_cid(plan) + "\"",
    ),
  )
  assert_true(
    @publication.publication_contract_json(attempt).contains(
      "\"publication_request_cid\":\"" +
      @publication.publication_contract_identity(request) +
      "\"",
    ),
  )
  assert_true(
    @publication.publication_contract_json(attempt).contains(
      "\"fence_cid\":\"sha256:" + "5".repeat(64) + "\"",
    ),
  )
  assert_false(
    @publication.publication_contract_json(attempt).contains(
      "external_idempotency_key",
    ),
  )
  assert_eq(@strategy.next_captured_task(run), first)
  assert_eq(usage.attempts, 0)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
  for index in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
    assert_false(@strategy.captured_task_completed(run, index))
  }
  @strategy.stop_captured_dag(run)
}

///|
test "Local publication intent refuses a bounded subset instead of shortening inventory" {
  let plan = plan(
    prepared(@input.Program(intent_program)),
    "bounded-intent-run",
  )
  let host = compute_host(plan)
  let run = local_compute_run(host)
  let first = @strategy.next_captured_task(run)
  assert_true(
    publication_intent_fixture(plan, max_results=1) is Err(InventoryLimit),
  )
  assert_true(
    publication_intent_fixture(plan, max_results=0) is Err(InventoryLimit),
  )
  assert_true(
    publication_intent_fixture(plan, max_wire_bytes=1) is Err(Contract(_)),
  )
  assert_eq(@strategy.next_captured_task(run), first)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
  assert_true(publication_intent_fixture(plan) is Ok(_))
  @strategy.stop_captured_dag(run)
}

///|
test "Local publication intent cannot be preflighted after pending active or completed Compute" {
  let input = prepared(@input.Program(intent_program))
  let plan = plan(input, "activation-intent-run")
  let host = compute_host(plan)
  let run = local_compute_run(host)
  assert_true(local_publication_compute_unstarted(run))
  let first = @strategy.next_captured_task(run).unwrap()
  @strategy.authorize_captured_task_activation(
    run,
    first,
    @strategy.task_activation_covered(),
  ).unwrap()
  assert_false(local_publication_compute_unstarted(run))
  // The normal activation Owner consumes its own current grant. No direct
  // state assignment or replacement Run represents active Compute.
  let current = account(Allow)
  let inputs : Array[@execution.ManagedCompletedOutput[Int]] = []
  let operations = start_local_compute_task(
      host,
      compute_start(host),
      inputs,
      permit(input, current),
      current,
      tuple(),
      context_cid(),
    )
    .unwrap()
    .unwrap()
  assert_false(local_publication_compute_unstarted(run))
  let mut executed = false
  for _ in 0..<1000 {
    if (operations.advance)(1).unwrap().complete {
      executed = true
      break
    }
  }
  assert_true(executed)
  let available = Ref(true)
  (operations.prepare_finalization)(first, operations.storage_bytes, () => {
    available.val
  }).unwrap()
  let mut finalized = false
  for _ in 0..<1000 {
    if (operations.advance_finalization)(1).unwrap().complete {
      finalized = true
      break
    }
  }
  assert_true(finalized)
  (operations.settle)().unwrap()
  (operations.complete)(first, operations.storage_bytes, () => available.val).unwrap()
  |> ignore
  assert_true(@strategy.captured_task_completed(run, first))
  assert_false(local_publication_compute_unstarted(run))
  assert_eq((operations.output_rows)(), 1)
  assert_eq((operations.output_row)(0).unwrap(), "{\"n\":1}")
  available.val = false
  (operations.close)()
  @strategy.close_captured_task_output(run, first)
  assert_true((operations.cleanup_refresh)())
  @strategy.stop_captured_dag(run)
}
