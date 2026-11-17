///|
// Real checked originals and Resource reservations; byte grants/provider
// ports are explicit fixtures, not installed backing or ordinary acceptance.
test "original snapshot is prepared before handoff and stays charged through continuation lifetime" {
  let calls = Ref(0)
  let (active, ledger, consumer) = original_observation_test_start(
    provider=original_funded_start_provider(calls),
    input_body=true,
  )
  while active.model is None {
    guard advance(active, 1).unwrap() is Continue(..) else {
      abort("same original must reach Model without dispatch")
    }
  }
  assert_eq(calls.val, 0)
  let body = active.identity_body.unwrap()
  let cached = body.snapshot.unwrap()
  assert_eq(call_scope_snapshot(active).unwrap(), cached)
  assert_eq(
    cached,
    @publication_host.client_infer_call_scope_snapshot(
      active.call_scope.unwrap(),
    ).unwrap(),
  )
  let before = @resources.ledger_usage(ledger)
  let bound = active.run_binding.unwrap()
  assert_true(
    @publication_host.grow_client_model_read_preparation_consumer_capacity(
      body.read,
      consumer,
      bound.compiled,
      bound.definition,
      active.plan.unwrap(),
      body.retained + 1L,
      body.execution + 1L,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(cancel(active))
  assert_true(call_scope_snapshot(active) is Err(_))
  assert_true(fixture_finish(active, initial_work=active.work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  // Model cleanup may drop Core's cache alias. The same Read still funds
  // the continuation's returned String until its enclosing retirement.
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    body.retained + 3L,
  )
  assert_true(cached.length() > 0)
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}

///|
test "snapshot wrapper quantity follows actual requested references rather than a128 fee" {
  let (active, ledger, consumer) = original_observation_test_start(
    input_body=true,
  )
  while active.model is None {
    guard advance(active, 1).unwrap() is Continue(..) else {
      abort("original snapshot must precede Model")
    }
  }
  let scope = active.call_scope.unwrap()
  let one = @publication_host.client_infer_scope_snapshot_construction_capacity(
    scope, 1,
  ).unwrap()
  let many = @publication_host.client_infer_scope_snapshot_construction_capacity(
    scope, 129,
  ).unwrap()
  // Three new arrays borrow one slot per occurrence. The shared collection
  // constructor covers current/old/new backing (three references per slot).
  // This is quantity arithmetic, not129 Model calls or physical bytes.
  assert_eq(
    @relation.execution_capacity_retained_bytes(many) -
    @relation.execution_capacity_retained_bytes(one),
    3L * 3L * 128L * 8L,
  )
  assert_eq(
    @relation.execution_capacity_execution_bytes(many) -
    @relation.execution_capacity_execution_bytes(one),
    3L * 3L * 128L * 8L,
  )
  assert_true(
    @publication_host.client_infer_scope_snapshot_construction_capacity(
      scope, -1,
    )
    is None,
  )
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=active.work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  original_composed_test_release(ledger, consumer)
}

///|
fn original_129_snapshot_fixture(
  durable_calls? : Bool = true,
  token_reservation? : Int64 = 128L,
  duration_ms? : Int64 = 1000L,
) -> (
  Execution,
  @resources.Ledger,
  @publication_host.ClientModelReadConsumer,
  Ref[Int],
) raise {
  let rows = Array::makei(129, i => {
    "{\"id\":\"r" + i.to_string() + "\",\"text\":\"hello\"}"
  })
  let document = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[" + rows.join(",") + "]",
  )
  // Author the larger task before Environment/Program admission. Its task
  // identity and the enclosing Environment identity follow the changed input;
  // the original two-item fixture and every production task limit stay intact.
  let environment_wire = @json.parse(infer_fixture_environment)
  guard environment_wire is Object(environment) &&
    environment["model_task_contracts"] is Array([task]) &&
    task is Object(fields) else {
    abort("original ModelTask fixture")
  }
  fields["max_items"] = Json::number(129)
  fields.remove("contract_cid") |> ignore
  fields["contract_cid"] = Json::string(
    "sha256:" + @sha.hex(@utf8.encode(fixture_canonical(task))),
  )
  environment.remove("evidence_bundle_cid") |> ignore
  let prepared = fixture_prepared(
    source=document,
    environment_wire=fixture_canonical(environment_wire),
  )
  let sequence = {
    ..@publication_host.client_standard_values_sequence_limits(),
    max_rows: 129,
  }
  let plan = call_identity_plan(
    prepared,
    attempts=258,
    token_reservation~,
    duration_ms~,
    wire_bytes=8583144L,
    sequence_limits=Some(sequence),
  )
  let base = standard_limits()
  let ledger_limits : @resources.LedgerLimits = {
    planning_work: 20000000,
    attempts: 258,
    holdings: 258,
    transfer_bytes: 8583144L,
    retained_bytes: 67108864L,
    execution_bytes: 67108864L,
  }
  // These are independent fixture grants before any read is issued. They
  // select no production defaults, actual physical backing or real LLM calls.
  let limits = {
    ..base,
    input: { ..base.input, rows: { ..base.input.rows, max_rows: 129, }, },
    mapping: {
      ..base.mapping,
      max_items: 129,
      logical: { ..base.mapping.logical, max_input_rows: 129L, },
    },
    model: {
      ..base.model,
      max_items: 129,
      max_work: 20000000,
      ledger: ledger_limits,
    },
    output_rows: 129,
    identity: { ..base.identity, rows: 129, },
  }
  let (compiled, _) = original_input_capacity_run(prepared, plan)
  // This fixture also publishes original observations. Select the genuine
  // source-free Result policy before issuing any Read/Scope/Run identity,
  // exactly as the existing original observation fixture does.
  let policy_wire = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let compiled = @publication_host.with_client_infer_result_policy(
    compiled,
    invocation_fixture_policy_cid(),
    policy_wire,
    16384,
    1024,
    20,
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "original-129", "run", "2026-10-12T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let ledger = @resources.create_ledger(ledger_limits).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 1024, 260, 0,
  ).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  // The compatibility fixture helper selects100 rows. This explicitly
  // bounded Host fixture instead prepares129 on the SAME checked owner via
  // its existing low-level sequence constructor. The Values-only row selector
  // is deliberately not used to reinterpret an INFER Program or grant bytes.
  let semantic = @lower.prepare_sequence_prefix(
    @publication_host.client_infer_occurrence_preparation(occurrence),
    1,
    sequence,
  ).unwrap()
  let contracts = @relation.admit_relation_registry(
    @canonical.from_json(
      @json.parse(infer_fixture_registry),
      10000,
      100,
      100000,
    ),
    @canonical.from_json(@json.parse(infer_fixture_values), 10000, 100, 100000),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let prefix = @relation.prepare_generated_sequence(
    contracts,
    semantic,
    [],
    [],
    100000,
    10000,
  ).unwrap()
  let calls = Ref(0)
  let active = start_original_composed(
    occurrence,
    plan,
    prefix,
    [],
    original_funded_start_provider(calls),
    limits,
    compiled,
    definition,
    consumer,
    7L,
    5L,
    4194304L,
    4194304L,
    input_body_read=Some(read),
  ).unwrap()
  active.durable_calls = durable_calls
  let configuration = evidence_account(@authorization.Allow)
  let permit = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    "fixture-principal",
    "2026-10-12T00:00:00.000Z",
    observe_current=() => Ok((configuration, "2026-10-12T00:00:00.000Z")),
  ).unwrap()
  bind_dispatch_admission(active, permit).unwrap()
  let mut selected = None
  let mut requests_ready = false
  for _ in 0..<200000 {
    if active.model is Some(model) &&
      @model.prepared_model_call_set(model) is Some(prepared) {
      selected = Some(prepared)
      break
    }
    if !durable_calls &&
      active.model is Some(model) &&
      @model.model_execution_prepared_request_bytes(model, 128) is Some(_) {
      requests_ready = true
      break
    }
    let polled = advance(active, 1).unwrap()
    guard polled is Continue(..) || active.phase is Model else {
      match polled {
        Failed(Model(issue), ..) => {
          println("129 preparation Model: " + issue.to_repr().to_string())
          abort("129 preparation Model")
        }
        Failed(Input(_), ..) => abort("129 preparation Input")
        Failed(IdentityExport(_), ..) => abort("129 preparation IdentityExport")
        Failed(CallScope(_), ..) => abort("129 preparation CallScope")
        Failed(OriginalCapacity(_), ..) =>
          abort("129 preparation OriginalCapacity")
        Failed(InvalidAdvance, ..) => abort("129 preparation InvalidAdvance")
        _ => abort("actual129 input must reach prepared calls before any send")
      }
    }
  }
  if durable_calls {
    assert_eq(@model.prepared_model_call_count(selected.unwrap()), Some(129))
  } else {
    assert_true(requests_ready)
  }
  assert_eq(calls.val, 0)
  assert_eq(
    call_scope_snapshot(active).unwrap(),
    active.identity_body.unwrap().snapshot.unwrap(),
  )
  (active, ledger, consumer, calls)
}

///|
test "one129 prepared call inventory retains its prefunded snapshot without any provider invocation" {
  let (active, ledger, consumer, calls) = original_129_snapshot_fixture()
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=active.work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
  original_composed_test_release(ledger, consumer)
}
