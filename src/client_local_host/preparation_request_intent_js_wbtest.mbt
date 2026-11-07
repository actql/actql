///|
test "Request native intent preserves exact Unicode Parameters options identity and current-free lookup" {
  let input = [1]
  let calls = Ref(0)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      calls.val += 1
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let document =
    #|{"input":{"format":"sql","text":"SELECT @n AS n"},"kind":"aql","parameters":{"é":"\r\n😀","n":2,"é":"x"},"readOnly":true,"stopBefore":"commit"}
  reserve_request_snapshot(
    parent,
    input,
    document.length().to_int64(),
    document.length().to_int64(),
  ).unwrap()
  let captured = request_native_test_value(document)
  let cid = prepare_request_submitted_intent(
    parent, input, captured, native_json_reader,
  ).unwrap()
  assert_eq(
    cid, "sha256:8dcee27f76e1b2d16a283ed1e18b3538bd569c13aec2611299548c57993306b5",
  )
  let intent = request_submitted_intent_original(parent, input).unwrap()
  assert_eq(@publication_host.client_submitted_intent_wire(intent), document)
  assert_true(
    @publication_host.client_submitted_intent_requests_commit_stop(intent),
  )
  assert_true(
    @publication_host.client_submitted_intent_requests_read_only(intent),
  )
  let peak = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  finish_request_submitted_intent(parent, input).unwrap()
  let retained = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  assert_true(retained.0 < peak.0 && retained.1 < peak.1)
  let before = calls.val
  assert_true(
    physical_equal(
      request_submitted_intent_original(parent, input).unwrap(),
      intent,
    ),
  )
  assert_eq(calls.val, before)
  assert_true(request_submitted_intent_original(parent, [1]) is None)
  assert_true(
    prepare_request_submitted_intent(
      parent, input, captured, native_json_reader,
    )
    is Err(WrongPhase),
  )
  assert_eq(calls.val, before)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(request_submitted_intent_original(parent, input) is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  // Phase receipts are finite known-work DATA, not Ledger planner visits or
  // physical attempts. Retain the SAME receipt's finished amount after stop.
  assert_eq(parent._observed_intent_work, document.length().to_int64())
}

///|
test "Request native intent refuses one-byte-short before reader construction on the same reservation" {
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    reserve_request_snapshot(parent, input, 128L, 32L).unwrap()
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let amount = request_intent_construction_bytes(
      128L,
      32L,
      request_captured_intent_limits(128L, 32L).unwrap(),
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - amount + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - amount + 1L
      },
    ).unwrap()
    let reads = Ref(0)
    let reader = {
      ..native_json_reader,
      kind: value => {
        reads.val += 1
        native_json_kind(value)
      },
    }
    let result = prepare_request_submitted_intent(
      parent,
      input,
      request_native_test_value(
        "{\"kind\":\"program\",\"input\":{},\"parameters\":null}",
      ),
      reader,
    )
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_eq(reads.val, 0)
    assert_false(parent.intent_attempted)
    assert_true(
      reserve_request_snapshot(parent, input, 256L, 64L) is Err(WrongPhase),
    )
    assert_true(
      prepare_request_native_program_input(
        parent,
        input,
        request_native_test_value(request_check_wire),
        reader,
        @publication_host.client_standard_program_preparation_limits().checking.input,
      )
      is Err(WrongPhase),
    )
    assert_true(
      parse_request_query_syntax(parent, input, "SELECT 1 AS n", @frontend.Sql)
      is Err(Request(WrongPhase)),
    )
    assert_eq(reads.val, 0)
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input).unwrap(),
      before,
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Request native intent keeps typed envelope failure and same failed constructor cleanup" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(parent, input, 128L, 32L).unwrap()
  let captured = request_native_test_value(
    "{\"kind\":\"program\",\"input\":{},\"parameters\":[]}",
  )
  assert_true(
    prepare_request_submitted_intent(parent, [1], captured, native_json_reader)
    is Err(ForeignOriginal),
  )
  assert_false(parent.intent_attempted)
  assert_true(
    prepare_request_submitted_intent(
      parent, input, captured, native_json_reader,
    )
    is Err(Intent(InvalidEnvelope)),
  )
  assert_true(
    parent.intent_attempted &&
    parent.intent_peak_live &&
    parent.intent_work is None,
  )
  assert_true(parent.submitted_intent is None)
  assert_true(finish_request_submitted_intent(parent, input) is Err(WrongPhase))
  assert_true(
    prepare_request_submitted_intent(
      parent, input, captured, native_json_reader,
    )
    is Err(WrongPhase),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request native intent enters the same Program checker module and Run without reissuing the parent" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(
    parent,
    input,
    request_check_wire.length().to_int64() + 64L,
    request_check_wire.length().to_int64() + 64L,
  ).unwrap()
  prepare_request_submitted_intent(
    parent,
    input,
    request_native_test_value(
      "{\"kind\":\"program\",\"input\":" +
      request_check_wire +
      ",\"parameters\":null}",
    ),
    native_json_reader,
  ).unwrap()
  |> ignore
  let program_input = request_native_test_value(request_check_wire)
  let limits = @publication_host.client_standard_program_preparation_limits()
  assert_true(
    prepare_request_native_program_input(
      parent,
      input,
      program_input,
      native_json_reader,
      limits.checking.input,
    )
    is Err(WrongPhase),
  )
  finish_request_submitted_intent(parent, input).unwrap()
  let source = match
    prepare_request_native_program_input(
      parent,
      input,
      program_input,
      native_json_reader,
      limits.checking.input,
    ) {
    Ok(value) => value
    Err(issue) =>
      fail("Original small native source: " + @debug.to_string(issue))
  }
  construct_program_json_preparation(source).unwrap()
  reconcile_program_json_preparation_structure(source).unwrap()
  let child = prepare_request_computation_check_preparation(
    parent,
    input,
    catalog_domain_environment(),
    None,
    [],
    limits,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  prepare_program_check_input(child).unwrap()
  prepare_program_check_prelude(child).unwrap() |> ignore
  prepare_program_check_registry(child).unwrap() |> ignore
  prepare_program_check_contents(child).unwrap() |> ignore
  prepare_program_check_references(child).unwrap() |> ignore
  prepare_program_check_policies(child).unwrap() |> ignore
  prepare_program_check_values(child).unwrap() |> ignore
  prepare_program_check_views(child).unwrap() |> ignore
  prepare_program_check_carriers(child).unwrap() |> ignore
  prepare_program_check_requests(child).unwrap() |> ignore
  reconcile_program_check_requests(child).unwrap()
  finish_request_computation_preparation(parent, input).unwrap()
  let prepared = parent.compiled_program.unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let held = borrow_request_program_preparation(parent).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "native-intent-same-request",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.return_preparation_body_borrow(held).unwrap())
  retire_installed_managed_run(run).unwrap()
  // Selected Root is no longer an input/Run issuer; exact Journal borrowing
  // and final handler alias retirement remain the normal caller's duties.
  assert_true(request_submitted_intent_original(parent, input) is None)
  assert_true(parent.submitted_intent is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request native intent retains the original reader exception until its frame has unwound" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(parent, input, 128L, 32L).unwrap()
  let reader = {
    ..native_json_reader,
    kind: _ => {
      ignore(closed_module_test_throw())
      0
    },
  }
  assert_true(
    closed_module_test_catch(() => {
      ignore(
        prepare_request_submitted_intent(
          parent,
          input,
          request_native_test_value("null"),
          reader,
        ),
      )
    }),
  )
  assert_true(
    parent.phase == Open &&
    parent.intent_peak_live &&
    parent.intent_work is Some(_),
  )
  assert_true(parent.submitted_intent is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.phase == Closed && parent.intent_work is None)
  assert_eq(parent._observed_intent_work, 128L)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "retained Request intent keeps the same original and observed long Text geometry" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let document = "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"" +
    "x".repeat(100000) +
    "\"},\"parameters\":null}"
  let intent = @publication_host.prepare_client_submitted_intent(
    document, 1048576, 65536, 64,
  ).unwrap()
  retain_request_submitted_intent(parent, input, intent).unwrap()
  assert_true(
    physical_equal(
      request_submitted_intent_original(parent, input).unwrap(),
      intent,
    ),
  )
  assert_true(parent.snapshot_values < 32L)
  assert_true(parent.snapshot_units >= 100000L)
  assert_eq(parent._observed_intent_work, document.length().to_int64() + 1L)
  assert_false(parent.intent_peak_live)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "retained Program material constructor grows the same original input before decoding" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":{},\"parameters\":null}", 1048576, 65536, 64,
  ).unwrap()
  retain_request_submitted_intent(parent, input, intent).unwrap()
  let before = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let base = parent.snapshot_base.unwrap()
  let units = parent.snapshot_units
  let values = parent.snapshot_values
  let wire = "{\"program_format\":\"json\",\"program\":\"{}\",\"parameters\":null}"
  let n = wire.length().to_int64() + 1L
  let amount = 3L * request_snapshot_data_bytes(n, n).unwrap()
  reserve_request_retained_program_material(parent, input, wire).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input).unwrap(),
    (before.0 + amount, before.1 + amount),
  )
  assert_eq(parent.snapshot_base, Some((base.0 + amount, base.1 + amount)))
  assert_eq(parent.snapshot_units, units)
  assert_eq(parent.snapshot_values, values)
  assert_true(
    physical_equal(
      request_submitted_intent_original(parent, input).unwrap(),
      intent,
    ),
  )
  assert_true(parent.program_json is None && !parent.native_parameters_ready)
  assert_true(parent.phase == Open)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "retained Program material constructor refuses one-short original capacity without changing its snapshot" {
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let intent = @publication_host.prepare_client_submitted_intent(
      "{\"kind\":\"program\",\"input\":{},\"parameters\":null}", 1048576, 65536,
      64,
    ).unwrap()
    retain_request_submitted_intent(parent, input, intent).unwrap()
    let wire = "{\"program_format\":\"json\",\"program\":\"{}\",\"parameters\":null}"
    let n = wire.length().to_int64() + 1L
    let amount = 3L * request_snapshot_data_bytes(n, n).unwrap()
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let base = parent.snapshot_base
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - amount + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - amount + 1L
      },
    ).unwrap()
    let result = reserve_request_retained_program_material(parent, input, wire)
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_eq(parent.snapshot_base, base)
    assert_true(parent.phase == Open)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "retained Program material constructor fences foreign input and original current reentry" {
  let input = [1]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let refused = Ref(false)
  let wire = "{}"
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if armed.val {
        armed.val = false
        refused.val = reserve_request_retained_program_material(
            selected.val.unwrap(),
            input,
            wire,
          )
          is Err(WrongPhase)
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  selected.val = Some(parent)
  assert_true(
    reserve_request_retained_program_material(parent, input, wire)
    is Err(WrongPhase),
  )
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":{},\"parameters\":null}", 1048576, 65536, 64,
  ).unwrap()
  retain_request_submitted_intent(parent, input, intent).unwrap()
  assert_true(
    reserve_request_retained_program_material(parent, [1], wire)
    is Err(ForeignOriginal),
  )
  armed.val = true
  reserve_request_retained_program_material(parent, input, wire).unwrap()
  assert_true(refused.val)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(
    reserve_request_retained_program_material(parent, input, wire)
    is Err(WrongPhase),
  )
}

///|
test "retained Request intent refuses a foreign input or replacement without a new identity" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1\"},\"parameters\":null}",
    1048576, 65536, 64,
  ).unwrap()
  assert_true(
    retain_request_submitted_intent(parent, [1], intent) is Err(ForeignOriginal),
  )
  assert_true(parent.submitted_intent is None)
  @debug.debug_inspect(
    retain_request_submitted_intent(parent, input, intent),
    content="Ok(())",
  )
  assert_true(
    retain_request_submitted_intent(parent, input, intent) is Err(WrongPhase),
  )
  assert_true(
    physical_equal(
      request_submitted_intent_original(parent, input).unwrap(),
      intent,
    ),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "retained Request intent refuses reentrant retention at its first current boundary" {
  let input = [1]
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1\"},\"parameters\":null}",
    1048576, 65536, 64,
  ).unwrap()
  let retained : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let refused = Ref(false)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if armed.val && retained.val is Some(original) {
        armed.val = false
        refused.val = retain_request_submitted_intent(original, input, intent)
          is Err(WrongPhase)
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  retained.val = Some(parent)
  armed.val = true
  retain_request_submitted_intent(parent, input, intent).unwrap()
  assert_true(refused.val)
  assert_true(
    physical_equal(
      request_submitted_intent_original(parent, input).unwrap(),
      intent,
    ),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  retained.val = None
}

///|
// The installed physical supplier is real; empty physical provider ports in
// the existing Plan fixture do not qualify Account/Host/vendor execution.
test "retained Request intent continues native Effect Parameters Plan and retirement on one parent" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let text =
    #|{"version":"actql/0.1","id":"native-effect","params":{"n":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"amount":"id + $n"},"as":"changed"}],"results":{"rows":{"from":"changed","fields":["id","amount"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"amount"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    text +
    ",\"parameters\":{\"n\":9},\"stopBefore\":\"commit\"}",
    1048576,
    65536,
    64,
  ).unwrap()
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let ledger = parent.ledger
  retain_request_submitted_intent(parent, input, intent).unwrap()
  assert_eq(
    prepare_request_native_computation(
      parent,
      input,
      request_native_test_value(text),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
      supplied=Some(request_native_test_value("{\"n\":9}")),
    ).unwrap(),
    Effect,
  )
  assert_true(physical_equal(parent.ledger, ledger))
  assert_true(
    physical_equal(
      request_submitted_intent_original(parent, input).unwrap(),
      intent,
    ),
  )
  let prepared = parent.compiled_effect.unwrap()
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  let task = @strategy.graph_task_owner(graph, 0).unwrap()
  assert_eq(
    @admitted.canonical_scalar_text(
      @lower.parameter_value(task, "n").unwrap(),
      32,
    ),
    Some("9"),
  )
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      prepared,
    ),
  )
  let (plan, original_request) = request_effect_plan_fixture(prepared)
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let managed = begin_request_effect_managed_run(parent, original_request).unwrap()
  assert_true(
    physical_equal(
      installed_effect_managed_operation_plan(
        managed, prepared, original_request,
      ).unwrap(),
      plan,
    ),
  )
  assert_true(retire_installed_managed_run(managed) is Err(CleanupPending))
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  retire_installed_managed_run(managed).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
// Fixture for the normal Local selector's two existing row projections. The
// generic 1000-row Environment used by other component fixtures is unchanged.
extern "js" fn request_numeric_local_environment(
  wire : String,
  rows : Int,
) -> String =
  #|(wire, rows) => {const value=JSON.parse(wire);delete value.evidence_bundle_cid;
  #| value.host_policy_profile.capacity.max_relation_output_rows=rows;
  #| value.host_policy_profile.capacity.max_artifact_rows=rows;
  #| const canonical=v=>Array.isArray(v)?'['+v.map(canonical).join(',')+']':v!==null&&typeof v==='object'?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}':JSON.stringify(v);
  #| value.evidence_bundle_cid='sha256:'+process.getBuiltinModule('node:crypto').createHash('sha256').update(canonical(value)).digest('hex');return canonical(value);}

///|
extern "js" fn request_numeric_environment_cid(wire : String) -> String =
  #|(wire) => JSON.parse(wire).evidence_bundle_cid

///|
test "original numeric 100000 intent uses its observed profile under the unchanged Request budget" {
  let program = request_native_numeric_public_program(100000)
  let document = "{\"kind\":\"program\",\"input\":" +
    program +
    ",\"parameters\":null}"
  assert_eq(document.length(), 1289220)
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(parent, input, 1703936L, 262144L).unwrap()
  let original_limits = @resources.ledger_limits(parent.ledger)
  let selected = request_default_program_preparation_limits(parent, input).unwrap()
  assert_true(
    selected.checking.input.source.max_input_bytes >= document.length(),
  )
  let baseline = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let quote = request_intent_construction_bytes(
    1703936L,
    262144L,
    selected.checking.input.source,
  ).unwrap()
  let cid = match
    prepare_request_submitted_intent(
      parent,
      input,
      request_native_test_value(document),
      native_json_reader,
    ) {
    Ok(value) => value
    Err(issue) =>
      fail(
        "Original100000 intent: " +
        @debug.to_string(issue) +
        "; constructor=" +
        quote.to_string() +
        "; baselineR=" +
        baseline.0.to_string() +
        "; baselineE=" +
        baseline.1.to_string() +
        "; selectedBytes=" +
        selected.checking.input.source.max_input_bytes.to_string() +
        "; selectedNodes=" +
        selected.checking.input.source.max_nodes.to_string(),
      )
  }
  let original = request_submitted_intent_original(parent, input).unwrap()
  assert_eq(cid, @publication_host.client_submitted_intent_cid(original))
  assert_true(
    @publication_host.client_submitted_intent_wire(original).length() > 1048576,
  )
  finish_request_submitted_intent(parent, input).unwrap()
  let continued = request_default_program_preparation_limits(parent, input).unwrap()
  assert_eq(
    continued.checking.input.source.max_input_bytes,
    selected.checking.input.source.max_input_bytes,
  )
  assert_eq(
    continued.checking.input.source.max_nodes,
    selected.checking.input.source.max_nodes,
  )
  assert_eq(
    continued.checking.input.source.max_depth,
    selected.checking.input.source.max_depth,
  )
  assert_eq(@resources.ledger_limits(parent.ledger), original_limits)
  let wire = request_numeric_local_environment(
    @publication_host.client_local_product_assets().environment,
    client_local_materialized_row_ceiling(client_local_resource_policy()).unwrap(),
  )
  let environment = @publication_host.admit_client_check_environment(
    wire,
    request_numeric_environment_cid(wire),
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let native = request_native_input_units(
    1703936L,
    262144L,
    selected.checking.input,
    max_key_units=Some(parent.snapshot_key_units.val),
  ).unwrap()
  let native_bytes = @execution.preparation_representation_cost(native).unwrap()
  let native_base = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  match
    prepare_request_native_computation(
      parent,
      input,
      request_native_test_value(program),
      native_json_reader,
      environment,
      publication,
      [],
      selected,
      @publication_host.client_standard_effect_computation_limits(),
    ) {
    Ok(Pure) => ()
    Ok(_) => fail("The same original numeric Program changed computation kind")
    Err(Preparation(ProgramCheck(issue))) => {
      let detail = match issue {
        Capacity(inner) => "Capacity " + @debug.to_string(inner)
        Check(_) => "Check"
        Catalog(_) => "Catalog"
        SourceRegistration(_) => "SourceRegistration"
        TopologyEntry(_) => "TopologyEntry"
        Prelude(_) => "Prelude"
        Compilation(_) => "Compilation"
        EffectInput(_) => "EffectInput"
        EffectCompilation(_) => "EffectCompilation"
        SourceInput(_) => "SourceInput"
        Work(_) => "Work"
        ChangedInputs => "ChangedInputs"
        WrongPhase => "WrongPhase"
        Overflow => "Overflow"
        RequestPolicySubjects(_) => "RequestPolicySubjects"
      }
      fail("Original100000 ProgramCheck: " + detail)
    }
    Err(Preparation(issue)) =>
      fail(
        "Original100000 native Program Preparation: " +
        @debug.to_string(issue) +
        "; constructor=" +
        native_bytes.to_string() +
        "; baselineR=" +
        native_base.0.to_string() +
        "; baselineE=" +
        native_base.1.to_string() +
        "; observedMaxKey=" +
        parent.snapshot_key_units.val.to_string() +
        "; nativeSourceReady=" +
        (parent.program_json is Some(_)).to_string(),
      )
    Err(CheckOutcome(outcome)) => {
      let detail = match outcome {
        @checked.Checked(_) => "Checked"
        @checked.NeedsInputs(_) => "NeedsInputs"
        @checked.Rejected(diagnostic) =>
          "Rejected " +
          @debug.to_string(@checked.diagnostic_category(diagnostic))
      }
      fail("Original100000 check outcome: " + detail)
    }
    Err(Publication(_)) => fail("Original100000 Publication")
    Err(QuerySyntax(_)) => fail("Original100000 QuerySyntax")
    Err(QueryLowering(_)) => fail("Original100000 QueryLowering")
  }
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  // A fresh process Request retains the SAME original Journal intent. Its
  // existing preflight supplies default geometry; it never uses the old cap.
  let restored_input = [2]
  let restored = begin_request_preparation(
    request_parent_fixture(restored_input),
    restored_input,
    client_local_resource_policy(),
  ).unwrap()
  retain_request_submitted_intent(restored, restored_input, original).unwrap()
  let restored_limits = request_default_program_preparation_limits(
    restored, restored_input,
  ).unwrap()
  assert_true(
    restored_limits.checking.input.source.max_input_bytes >= document.length(),
  )
  assert_true(restored_limits.checking.input.source.max_nodes >= 200026)
  assert_true(
    physical_equal(
      request_submitted_intent_original(restored, restored_input).unwrap(),
      original,
    ),
  )
  assert_eq(@resources.ledger_limits(restored.ledger), original_limits)
  abort_request_preparation_after_cleanup(restored).unwrap()
  assert_eq(@resources.ledger_usage(restored.ledger).live_reservations, 0)
}
