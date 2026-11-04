///|
let native_driver_program : String =
  #|{"version":"actql/0.1","id":"native-driver","params":{"n":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"日本語😀"}]},"as":"seed"},{"derive":{"value":"id + $n"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","label","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
fn native_driver_parent(
  text : String,
) -> (ClientRequestPreparation[Array[Int]], Array[Int]) {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  // Conservative actual-capture envelope for this component. The distinct
  // Node manager case observes the SDK's own supplied snapshot quantities.
  reserve_request_snapshot(
    parent,
    input,
    text.length().to_int64() + 32L,
    text.length().to_int64() + 32L,
  ).unwrap()
  (parent, input)
}

///|
test "normal Native driver keeps original supplied Parameters Text compiler module and Run" {
  let (environment, publication) = request_query_publication_fixture()
  for supplied in [false, true] {
    let (parent, input) = native_driver_parent(native_driver_program)
    assert_eq(
      prepare_request_native_computation(
        parent,
        input,
        request_native_test_value(native_driver_program),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
        supplied=if supplied {
          Some(request_native_test_value("{\"n\":9}"))
        } else {
          None
        },
      ).unwrap(),
      Pure,
    )
    let prepared = parent.compiled_program.unwrap()
    let cursor = request_preparation_parameters_original(parent, input).unwrap()
    if supplied {
      assert_true(cursor is Some(_))
    } else {
      assert_true(cursor is None)
    }
    let before = @resources.ledger_usage(parent.ledger)
    assert_true(
      prepare_request_native_computation(
        parent,
        input,
        request_native_test_value(native_driver_program),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
      )
      is Err(Preparation(WrongPhase)),
    )
    assert_eq(@resources.ledger_usage(parent.ledger), before)
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=_ => [],
    ).unwrap()
    let holder = borrow_request_program_preparation(parent).unwrap()
    assert_true(
      physical_equal(
        @resources.preparation_body_borrow_value(holder).unwrap(),
        prepared,
      ),
    )
    let plan = parent.program_source_free.unwrap()
    let request = @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "native-driver",
    ).unwrap()
    let run = begin_request_program_managed_run(parent, request).unwrap()
    let setup = open_installed_managed_source_free_host(
        run,
        prepared,
        request,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
        true,
      )
      .unwrap()
      .unwrap()
    let output = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
      true
    }).unwrap()
    assert_eq(
      output.rows().unwrap(),
      if supplied {
        ["{\"id\":1,\"label\":\"日本語😀\",\"value\":10}"]
      } else {
        ["{\"id\":1,\"label\":\"日本語😀\",\"value\":8}"]
      },
    )
    assert_true(output.close())
    assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
    @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "normal Native driver preserves the original typed rejected check and pending parent cleanup" {
  let (environment, publication) = request_query_publication_fixture()
  let text = request_check_wire.replace(old="\"take\":1", new="\"take\":-1")
  let (parent, input) = native_driver_parent(text)
  assert_true(
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
    )
    is Err(CheckOutcome(_)),
  )
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  let work = @resources.ledger_usage(parent.ledger).planning_work
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).planning_work, work)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "normal Native driver keeps the original Effect branch and its native Parameter cursor" {
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
  let (parent, input) = native_driver_parent(text)
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
  let cursor = request_preparation_parameters_original(parent, input)
    .unwrap()
    .unwrap()
  assert_true(physical_equal(cursor, parent.native_parameters.unwrap()))
  assert_true(
    parent.compiled_effect is Some(_) && parent.compiled_program is None,
  )
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      parent.compiled_effect.unwrap(),
    ),
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "normal Query driver retains native SQL AQL originals through one compiler module and Run" {
  let (environment, publication) = request_query_publication_fixture()
  for
    (document, format) in [
      ("SELECT @text AS label", @frontend.Sql),
      (
        "WITH seed AS (SELECT @text AS label) FROM seed |> SELECT label",
        @frontend.Text,
      ),
    ] {
    let (parent, input) = native_driver_parent(
      document + " declaration and supplied 日本語😀",
    )
    let reads = Ref(0)
    let reader = {
      ..native_json_reader,
      field: fn(value, key) {
        reads.val += 1
        (native_json_reader.field)(value, key)
      },
    }
    let supplied = request_native_test_value("{\"text\":\"日本語😀\"}")
    let declarations = request_native_test_value(
      "{\"text\":{\"type\":\"string\"}}",
    )
    assert_eq(
      prepare_request_native_query_computation(
        parent,
        input,
        document,
        format,
        reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
        supplied=Some(supplied),
        declarations=Some(declarations),
      ).unwrap(),
      Pure,
    )
    let syntax = parent.query_syntax.unwrap()
    let original = syntax.lowering.unwrap().output.unwrap().unwrap()
    assert_true(
      physical_equal(parent.held_program.unwrap(), original.0.program.unwrap()),
    )
    assert_true(
      physical_equal(
        original.1,
        @source_publication.prepared_published_query_catalog(
          publication, environment,
        ).unwrap(),
      ),
    )
    let parameters = request_preparation_parameters_original(parent, input)
      .unwrap()
      .unwrap()
    assert_true(physical_equal(parameters, parent.native_parameters.unwrap()))
    let before_reads = reads.val
    let before = @resources.ledger_usage(parent.ledger)
    assert_true(
      prepare_request_native_query_computation(
        parent,
        input,
        document,
        format,
        reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
        supplied=Some(supplied),
        declarations=Some(declarations),
      )
      is Err(Preparation(WrongPhase)),
    )
    assert_eq(reads.val, before_reads)
    assert_eq(@resources.ledger_usage(parent.ledger), before)
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
    let holder = borrow_request_program_preparation(parent).unwrap()
    let plan = parent.program_source_free.unwrap()
    let request = @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "native-query-driver",
    ).unwrap()
    let run = begin_request_program_managed_run(parent, request).unwrap()
    assert_true(
      parent.native_query_declarations is None &&
      parent.native_parameters is None,
    )
    let setup = open_installed_managed_source_free_host(
        run,
        prepared,
        request,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
        true,
      )
      .unwrap()
      .unwrap()
    let output = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
      true
    }).unwrap()
    assert_eq(output.rows().unwrap(), ["{\"label\":\"日本語😀\"}"])
    assert_true(output.close())
    assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
    @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Query input controls absent native data adds no current callback before the parser quote" {
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
  reserve_request_snapshot(parent, input, 100L, 100L).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let observed = calls.val
  prepare_request_native_query_input(
    parent,
    input,
    native_json_reader,
    None,
    None,
  ).unwrap()
  assert_eq(calls.val, observed)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(
    parent.native_parameters_ready &&
    parent.native_parameters is None &&
    parent.native_query_declarations is None,
  )
  parse_request_query_syntax(parent, input, "SELECT 1 AS n", @frontend.Sql).unwrap()
  |> ignore
  assert_eq(calls.val - observed, 1)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Query input controls preserve supplied refusal before declarations and query syntax" {
  let (parent, input) = native_driver_parent("parameters and declarations")
  let declarations = request_native_test_value("null")
  let visits = Ref(0)
  let reader = {
    ..native_json_reader,
    kind: fn(value) {
      if physical_equal(value, declarations) {
        visits.val += 1
      }
      (native_json_reader.kind)(value)
    },
  }
  assert_true(
    prepare_request_native_query_input(
      parent,
      input,
      reader,
      Some(request_native_test_value("{\"é\":1,\"é\":2}")),
      Some(declarations),
    )
    is Err(Preparation(Parameters(_))),
  )
  assert_eq(visits.val, 0)
  assert_true(parent.query_syntax is None && !parent.native_parameters_ready)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Query input controls retain nominal NULL declaration refusal and clear original cursor" {
  let (parent, input) = native_driver_parent("supplied and NULL declaration")
  assert_true(
    prepare_request_native_query_input(
      parent,
      input,
      native_json_reader,
      Some(request_native_test_value("{\"text\":\"日本語😀\"}")),
      Some(request_native_test_value("null")),
    )
    is Err(Publication(Publication(@source_publication.Declarations))),
  )
  assert_true(
    parent.native_parameters is Some(_) && parent.query_syntax is None,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(
    parent.native_parameters is None && parent.native_query_declarations is None,
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Query input controls one short grow refuses before either original native tree" {
  let supplied = request_native_test_value("{\"text\":\"日本語😀\"}")
  let declarations = request_native_test_value(
    "{\"text\":{\"type\":\"string\"}}",
  )
  let (observed, original) = native_driver_parent("same actual input shape")
  let before = @resources.ledger_usage(observed.ledger)
  prepare_request_native_query_input(
    observed,
    original,
    native_json_reader,
    Some(supplied),
    Some(declarations),
  ).unwrap()
  let after = @resources.ledger_usage(observed.ledger)
  let required_r = after.reserved_retention_bytes -
    before.reserved_retention_bytes
  let required_e = after.reserved_execution_bytes -
    before.reserved_execution_bytes
  assert_true(required_r > 0L && required_e > 0L)
  abort_request_preparation_after_cleanup(observed).unwrap()
  for retention in [true, false] {
    let (parent, input) = native_driver_parent("same actual input shape")
    let base = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - base.reserved_retention_bytes - required_r + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - base.reserved_execution_bytes - required_e + 1L
      },
    ).unwrap()
    let reads = Ref(0)
    let reader = {
      ..native_json_reader,
      kind: fn(value) {
        reads.val += 1
        (native_json_reader.kind)(value)
      },
    }
    assert_true(
      prepare_request_native_query_input(
        parent,
        input,
        reader,
        Some(supplied),
        Some(declarations),
      )
      is Err(Preparation(Capacity(_))),
    )
    assert_eq(reads.val, 0)
    assert_true(
      parent.native_parameters is None &&
      parent.native_query_declarations is None &&
      parent.query_syntax is None,
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Query input controls keep the selected reuse wrapper and refuse a foreign Catalog original" {
  let (environment, publication) = request_query_publication_fixture()
  let (_, foreign_publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent("SELECT 1 AS n")
  parse_request_query_syntax(parent, input, "SELECT 1 AS n", @frontend.Sql).unwrap()
  |> ignore
  let lowered = lower_request_published_query(
    parent,
    input,
    publication,
    environment,
    None,
  ).unwrap()
  let (foreign_environment, _) = request_query_publication_fixture()
  // This second publication has a separately admitted Environment/Catalog,
  // despite the exact same authored immutable product documents/CID.
  let foreign = @source_publication.prepared_published_query_catalog(
    foreign_publication, foreign_environment,
  )
  assert_true(foreign is Err(@source_publication.ForeignEnvironment))
  let (other_environment, other_publication) = request_query_publication_fixture()
  let foreign = @source_publication.prepared_published_query_catalog(
    other_publication, other_environment,
  ).unwrap()
  assert_eq(
    @checked.checking_environment_cid(other_environment),
    @checked.checking_environment_cid(environment),
  )
  assert_true(!@checked.source_catalog_same_original(foreign, lowered.1))
  assert_true(
    prepare_request_program_check_preparation(
      parent,
      input,
      environment,
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
      source_catalog=Some(@checked.require_source_catalog_reuse(foreign)),
    )
    is Err(ForeignOriginal),
  )
  let required = @checked.require_source_catalog_reuse(lowered.1)
  let child = prepare_request_program_check_preparation(
    parent,
    input,
    environment,
    None,
    [],
    @publication_host.client_standard_program_preparation_limits().checking,
    source_catalog=Some(required),
  ).unwrap()
  assert_true(
    physical_equal(child.arguments.unwrap().source_catalog.unwrap(), required),
  )
  assert_true(
    @checked.source_catalog_requires_reuse(
      child.arguments.unwrap().source_catalog.unwrap(),
    ),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Query input controls fence same parent cleanup and replacement during native construction" {
  let (parent, input) = native_driver_parent("original native query")
  let flags = Ref(0)
  let reader = {
    ..native_json_reader,
    field: fn(value, key) {
      if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
        flags.val = flags.val | 1
      }
      if prepare_request_native_query_input(
          parent,
          input,
          native_json_reader,
          None,
          None,
        )
        is Err(Preparation(WrongPhase)) {
        flags.val = flags.val | 2
      }
      (native_json_reader.field)(value, key)
    },
  }
  prepare_request_native_query_input(
    parent,
    input,
    reader,
    Some(request_native_test_value("{\"text\":\"original\"}")),
    Some(request_native_test_value("{\"text\":{\"type\":\"string\"}}")),
  ).unwrap()
  assert_eq(flags.val, 3)
  assert_true(
    parent.native_parameters_ready &&
    parent.native_query_declarations is Some(_),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.native_query_declarations is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "native policy boundary finishes the same checked input without native reads" {
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(native_driver_program)
  let reads = Ref(0)
  let reader = {
    ..native_json_reader,
    field: fn(value, key) {
      reads.val += 1
      (native_json_reader.field)(value, key)
    },
  }
  prepare_request_native_computation_check(
    parent,
    input,
    request_native_test_value(native_driver_program),
    reader,
    environment,
    publication,
    [],
    @publication_host.client_standard_program_preparation_limits(),
    @publication_host.client_standard_effect_computation_limits(),
    supplied=Some(request_native_test_value("{\"n\":9}")),
  ).unwrap()
  let child = parent.program_check.unwrap()
  let program = parent.held_program.unwrap()
  let parameters = parent.native_parameters.unwrap()
  let capacity = parent.capacity
  assert_true(child.phase == SemanticCheckComplete)
  assert_true(
    parent.compiled_program is None && parent.program_capacity is None,
  )
  let before_reads = reads.val
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    physical_equal(
      supplement_request_computation_policies(parent, input, environment, []).unwrap(),
      environment,
    ),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  assert_eq(reads.val, before_reads)
  assert_true(child.phase == Transferred && parent.program_check is None)
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(physical_equal(parent.native_parameters.unwrap(), parameters))
  assert_true(physical_equal(parent.capacity, capacity))
  let compiled = parent.compiled_program.unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let holder = borrow_request_program_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      compiled,
    ),
  )
  assert_eq(reads.val, before_reads)
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "native policy boundary preserves all Source formats before one same-input finish" {
  let (environment, publication) = request_query_publication_fixture()
  for
    (document, format) in [
      (native_driver_program, "json"),
      (native_driver_program, "aql-json"),
      (request_document_yaml, "yaml"),
      (request_document_yaml, "aql-yaml"),
      ("SELECT '日本語😀' AS label", "sql"),
      (
        "WITH seed AS (SELECT '日本語😀' AS label) FROM seed |> SELECT label",
        "aql-text",
      ),
    ] {
    let (parent, input) = native_driver_parent(document)
    let reads = Ref(0)
    let reader = {
      ..native_json_reader,
      field: fn(value, key) {
        reads.val += 1
        (native_json_reader.field)(value, key)
      },
    }
    prepare_request_native_source_computation_check(
      parent,
      input,
      request_document_test_source(document, format),
      reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap()
    let child = parent.program_check.unwrap()
    let program = parent.held_program.unwrap()
    let syntax = parent.query_syntax
    assert_true(child.phase == SemanticCheckComplete)
    assert_true(
      parent.compiled_program is None && parent.program_capacity is None,
    )
    let before_reads = reads.val
    assert_eq(
      finish_request_checked_computation(
        parent, input, environment, publication,
      ).unwrap(),
      Pure,
    )
    assert_eq(reads.val, before_reads)
    assert_true(physical_equal(parent.held_program.unwrap(), program))
    match syntax {
      Some(original) =>
        assert_true(physical_equal(parent.query_syntax.unwrap(), original))
      None => assert_true(parent.query_syntax is None)
    }
    assert_true(child.phase == Transferred)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "native policy boundary rejects another installation before finishing original policies" {
  let environment = request_policy_supplement_environment()
  let (parent, input) = request_policy_supplement_fixture(
    environment,
    supplied=true,
  )
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let child = parent.program_check.unwrap()
  // Equal installation DATA is not the Catalog original retained by checking.
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    finish_request_checked_computation(parent, input, environment, publication)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "native policy boundary compiles selected evidence with the original publication" {
  let environment = request_policy_supplement_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, input) = native_driver_parent(policy_supplement_program)
  prepare_request_native_computation_check(
    parent,
    input,
    request_native_test_value(policy_supplement_program),
    native_json_reader,
    environment,
    publication,
    [],
    @publication_host.client_standard_program_preparation_limits(),
    @publication_host.client_standard_effect_computation_limits(),
    supplied=Some(request_native_test_value("{\"key\":1}")),
  ).unwrap()
  let child = parent.program_check.unwrap()
  let program = parent.held_program.unwrap()
  let parameters = parent.native_parameters.unwrap()
  let selected = supplement_request_computation_policies(
    parent,
    input,
    environment,
    [request_policy_supplement_evidence(parent)],
  ).unwrap()
  assert_false(physical_equal(selected, environment))
  assert_true(physical_equal(parent.program_check.unwrap(), child))
  assert_true(child.phase == SemanticCheckComplete)
  assert_true(
    parent.compiled_program is None && parent.program_capacity is None,
  )
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  assert_true(child.phase == Transferred)
  assert_true(physical_equal(parent.held_program.unwrap(), program))
  assert_true(physical_equal(parent.native_parameters.unwrap(), parameters))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
