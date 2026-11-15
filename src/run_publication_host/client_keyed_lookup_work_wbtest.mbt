///|
// Independent authored Resource envelope; only this fixture issuer accepts it.
fn keyed_work_resource() -> String {
  "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"content-fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}"
}

///|
// Actual checked generic Source capture and Request/lookup originals. This
// component has no provider send, durable Store or physical stop acceptance.
fn keyed_work_original_fixture(
  rows_wire : String,
  max_rows : Int,
  max_work : Int,
  completion? : Bool = false,
  resources? : Array[String]? = None,
) -> (ClientKeyedLookupInput, () -> Bool, @row_host.RowDeclaration) raise {
  let (prepared, keyed, declaration) = generic_file_effect_fixture(
    whole=true,
    lookup_bytes=if completion { 1000000 } else { 32768 },
  )
  let measured = measure_client_effect_generic_keyed_plan_construction(
    prepared,
    keyed,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let graph = issue_client_effect_keyed_plan_graph(
    measured, 1000000, 100000, 100,
  ).unwrap()
  guard graph.component is GenericKeyedPlan(component) else {
    fail("generic checked component")
  }
  let generated = @execution.prepare_generated_sequence(
    whole_source_capture_contracts(),
    component.original.fragments.joined.sequence,
    [],
    [],
    10000,
    1000000,
  ).unwrap()
  let limits = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "generic-scope", "generic-original", "2026-11-15T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = client_effect_allowed_keyed_run(allowed, graph, definition).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "generic-whole",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: if completion {
      1024
    } else {
      100
    },
    holdings: if completion {
      1024
    } else {
      100
    },
    // The Source still owns its 1MiB transfer reservation while the 101
    // component children each retain their existing 8192-byte envelope.
    transfer_bytes: if completion {
      2000000L
    } else {
      1000000L
    },
    retained_bytes: if completion {
      536870912L
    } else {
      67108864L
    },
    execution_bytes: if completion {
      536870912L
    } else {
      67108864L
    },
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 100000L, 100000L).unwrap()
  let inventory = @resources.begin_original_ledger_inventory(
    ledger,
    bootstrap,
    if completion {
      1024
    } else {
      50
    },
    if completion {
      1024
    } else {
      50
    },
    0,
  ).unwrap()
  let parent = bind_client_effect_keyed_original(
    prepared, compilation, compiled, definition, request, graph, keyed, ledger, inventory,
  ).unwrap()
  let original = prepare_client_effect_source_acquisition(prepared, 0, 0).unwrap()
  let owner = @strategy.graph_task_owner(
    @strategy.checked_effect_computation_graph(prepared.graph),
    0,
  ).unwrap()
  let sequence = @lower.prepare_sequence_prefix(owner, 0, limits.sequence).unwrap()
  let selected = @row_host.prepare_row_input_acquisition(
    original,
    @checked.source_identity(
      @strategy.graph_program(
        @strategy.checked_effect_computation_graph(prepared.graph),
      ),
    ),
    sequence,
    whole_source_capture_contracts(),
    declaration,
    {
      max_rows,
      page: { max_bytes: 1000000, max_nodes: 100000, max_depth: 20, max_rows, },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 1000000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire: {
        max_columns: 10,
        max_order_work: 10000,
        max_bytes: 1000000,
        max_nodes: 10000,
        max_depth: 20,
      },
    },
  ).unwrap()
  let settled = Ref(false)
  let stopped = Ref(false)
  let run = @row_host.start_accounted_row_input_acquisition(
    selected,
    None,
    "generic-source",
    _ => settled.val,
    ledger,
    1000000L,
    1000000L,
  ).unwrap()
  @row_host.begin_row_run_with_page_limits(
    run,
    { max_bytes: 1000000, max_nodes: 100000, max_depth: 20, max_rows, },
    max_rows,
    reference_issuer=Some(
      @values.bind_reference_issuer(
        (_, wire) => {
          resources
          .map(values => values.contains(wire))
          .unwrap_or(wire == keyed_work_resource())
        },
        _ => true,
      ),
    ),
  ).unwrap()
  let responses = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(responses, () => stopped.val).unwrap()
  let bytes = @utf8.encode(rows_wire)
  let charge = @row_host.charge_row_run_page(run, bytes).unwrap()
  assert_eq(
    @row_host.accept_charged_row_run_page(run, charge, bytes).unwrap(),
    max_rows,
  )
  @row_host.finish_row_run(run).unwrap()
  settled.val = true
  assert_true(whole_row_validate(run))
  let capture = @row_host.capture_row_run(run).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  let rows = @row_host.row_capture_input(capture).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 1000000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let identity = @query.identify_captured_source_relation(
    source,
    max_rows,
    {
      max_nodes: 10000,
      max_text_bytes: 1000000,
      max_depth: 20,
      max_work: 1000000,
    },
    wire,
    wire,
    { max_fields: 10, max_bytes: 1000000, max_nodes: 10000, max_depth: 20, },
    1000000,
    retain_body_bytes=1000000,
  ).unwrap()
  let logical = issue_captured_whole_source_input_logical(
    @strategy.checked_effect_computation_graph(prepared.graph),
    source,
    identity,
    original,
    task=0,
  ).unwrap()
  let observation = @row_host.issue_row_input_source_evidence(
    selected,
    capture,
    identity,
    logical,
    client_request_authority_scope_cid(request),
    @planning.source_acquisition_evidence_facts(original).unwrap().source_data_policy_cid,
    "2026-11-15T00:00:01.000Z",
  ).unwrap()
  let lookup = start_client_effect_keyed_capture_lookup_input(
    parent,
    [rows],
    10000,
    10000,
    1000000,
    max_work,
    source_sequence=Some(generated),
  ).unwrap()
  if completion {
    prepare_client_effect_keyed_generic_source_metadata(
      parent,
      lookup,
      identity,
      logical,
      observation,
      "sha256:" + "d".repeat(64),
      "2099-01-01T00:00:00.000Z",
      "2099-01-02T00:00:00.000Z",
      "2099-01-03T00:00:00.000Z",
      "sha256:" + "e".repeat(64),
      "sha256:" + "f".repeat(64),
      1000000,
      100000,
      100,
    ).unwrap()
    |> ignore
  }
  let closed = Ref(false)
  let cleanup = fn() {
    if closed.val {
      return true
    }
    stop_client_keyed_lookup_input(lookup)
    while !cleanup_client_keyed_lookup_input(lookup, 64).unwrap() {

    }
    stopped.val = true
    @row_host.close_accounted_row_run(run).unwrap()
    let finished = @resources.finish_original_ledger_inventory(ledger, true).unwrap()
    let usage = @resources.ledger_usage(ledger)
    closed.val = finished &&
      usage.reserved_retention_bytes == 0L &&
      usage.reserved_execution_bytes == 0L
    closed.val
  }
  (lookup, cleanup, declaration)
}

///|
test "keyed canonical request search fits original finite work for 101 distinct versions" {
  // Resource envelope is an independently authored fixture, not execution
  // authority. Versions are distinct and their physical requests are never sent.
  let resource = keyed_work_resource()
  let rows = Array::makei(101, index => {
    "{\"path\":\"same.txt\",\"resource\":" +
    resource +
    ",\"version\":\"v" +
    index.to_string() +
    "\"}"
  })
  let (lookup, cleanup, _) = keyed_work_original_fixture(
    "[" + rows.join(",") + "]",
    101,
    1000000,
  )
  defer cleanup() |> ignore
  start_client_keyed_lookup_request_plan(lookup).unwrap()
  for row in 0..<101 {
    let preparation = start_client_keyed_lookup_request(lookup, row).unwrap()
    let mut original = None
    for _ in 0..<10000 {
      match advance_client_keyed_lookup_request(lookup, preparation) {
        ClientKeyedRequestContinue(..) => ()
        ClientKeyedRequestComplete(request, ..) => {
          original = Some(request)
          break
        }
        ClientKeyedRequestFailed(_, ..) => fail("request construction failed")
      }
    }
    let request = original.unwrap()
    let retained = retain_client_keyed_lookup_planned_request(lookup, request)
    if retained is Err(_) {
      println(
        "KEYED_WORK row=\{row} allowance=\{lookup.max_work} spent=\{client_keyed_lookup_input_work(lookup)} charged=\{lookup.work}",
      )
    }
    retained.unwrap()
  }
  assert_eq(lookup.known.length(), 101)
  assert_true(client_keyed_lookup_input_work(lookup) <= 1000000L)
  println(
    "KEYED_WORK complete allowance=\{lookup.max_work} spent=\{client_keyed_lookup_input_work(lookup)}",
  )
  let original_order = lookup.key_order
  assert_true(cleanup())
  assert_true(lookup.key_order.is_empty())
  assert_false(physical_equal(lookup.key_order, original_order))
}

///|
fn keyed_work_request(
  lookup : ClientKeyedLookupInput,
  row : Int,
) -> ClientKeyedRequest raise {
  let preparation = start_client_keyed_lookup_request(lookup, row).unwrap()
  for _ in 0..<10000 {
    match advance_client_keyed_lookup_request(lookup, preparation) {
      ClientKeyedRequestContinue(..) => ()
      ClientKeyedRequestComplete(request, ..) => return request
      ClientKeyedRequestFailed(_, ..) => fail("actual keyed Request failed")
    }
  }
  fail("actual keyed Request did not complete")
}

///|
fn keyed_work_rows(count : Int) -> String {
  "[" +
  Array::makei(count, index => {
    "{\"path\":\"same.txt\",\"resource\":" +
    keyed_work_resource() +
    ",\"version\":\"v" +
    index.to_string() +
    "\"}"
  }).join(",") +
  "]"
}

///|
test "keyed canonical slot comparison preserves one-short original work refusal" {
  let (lookup, cleanup, _) = keyed_work_original_fixture(
    keyed_work_rows(2),
    2,
    1000000,
  )
  defer cleanup() |> ignore
  start_client_keyed_lookup_request_plan(lookup).unwrap()
  let first = keyed_work_request(lookup, 0)
  retain_client_keyed_lookup_planned_request(lookup, first).unwrap()
  let second = keyed_work_request(lookup, 1)
  // Independently authored canonical request body. Planning encodes it once
  // and charges those bytes before its actual slot comparison.
  let wire = "{\"resource\":" + keyed_work_resource() + ",\"version\":\"v1\"}"
  // The fixed canonical versions first differ at the digit before the final
  // two delimiters. Length is compared once; each inspected UTF-16 pair costs2.
  let probe = 1 + 2 * (wire.length() - 2)
  let spent = client_keyed_lookup_input_work(lookup).to_int()
  assert_true(
    charge_keyed_lookup_input_work(
      lookup,
      lookup.max_work - spent - (wire.length() + probe - 1),
    ),
  )
  let before = client_keyed_lookup_input_work(lookup)
  assert_true(
    retain_client_keyed_lookup_planned_request(lookup, second)
    is Err(LookupLimit("work")),
  )
  assert_eq(
    client_keyed_lookup_input_work(lookup),
    before + wire.length().to_int64() + probe.to_int64() - 2L,
  )
  assert_eq(lookup.known.length(), 1)
  assert_eq(lookup.key_order, [0])
  assert_true(find_client_keyed_lookup_response(lookup, second) is Err(_))
  assert_true(cleanup())
}

///|
test "keyed canonical slot insertion requires original retained backing before mutation" {
  let (lookup, cleanup, _) = keyed_work_original_fixture(
    keyed_work_rows(1),
    1,
    1000000,
  )
  defer cleanup() |> ignore
  start_client_keyed_lookup_request_plan(lookup).unwrap()
  let request = keyed_work_request(lookup, 0)
  let usage = @resources.ledger_usage(lookup.ledger)
  let available = @resources.ledger_limits(lookup.ledger).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let blocker = @resources.reserve_capacity(lookup.ledger, available, 0L).unwrap()
  defer @resources.settle_capacity(lookup.ledger, blocker) |> ignore
  assert_true(
    retain_client_keyed_lookup_planned_request(lookup, request)
    is Err(Physical(@resources.RetentionLimit)),
  )
  assert_true(lookup.known.is_empty() && lookup.key_order.is_empty())
  assert_eq(lookup.planned_requests.unwrap().length(), 0)
}

///|
test "keyed canonical slot index cannot admit foreign or stopped Request originals" {
  let (lookup, cleanup, _) = keyed_work_original_fixture(
    keyed_work_rows(1),
    1,
    1000000,
  )
  defer cleanup() |> ignore
  let (foreign, cleanup_foreign, _) = keyed_work_original_fixture(
    keyed_work_rows(1),
    1,
    1000000,
  )
  defer cleanup_foreign() |> ignore
  let original = keyed_work_request(lookup, 0)
  let other = keyed_work_request(foreign, 0)
  assert_true(
    find_client_keyed_lookup_response(lookup, other)
    is Err(Assembly("foreign_or_unavailable_request")),
  )
  assert_true(lookup.known.is_empty() && lookup.key_order.is_empty())
  stop_client_keyed_lookup_input(lookup)
  assert_true(
    find_client_keyed_lookup_response(lookup, original)
    is Err(Assembly("foreign_or_unavailable_request")),
  )
  assert_true(cleanup())
  assert_true(cleanup_foreign())
}
