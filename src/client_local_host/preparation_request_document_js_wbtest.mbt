///|
extern "js" fn request_document_test_source(
  document : String,
  format : String,
) -> NativeJsonValue =
  #|(text,format) => ({text,format})

///|
test "default Source Request rejects the original incompatible membership annotation" {
  let text = "SELECT 2 IN UNNEST(ARRAY<STRING>[1]) AS found"
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(text)
  let result = prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(text, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  )
  assert_true(
    result is Err(CheckOutcome(@checked.Rejected(_))),
    msg="the original Request must preserve the annotation's semantic refusal",
  )
  assert_true(parent.compiled_program is None && parent.compiled_effect is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "default Source Request keeps canonical signed zero in scalar membership" {
  let text = "SELECT 2 IN UNNEST([-(0)]) AS found"
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(text)
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(text, "sql"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  assert_true(
    parent.program_check.unwrap().check_outcome is Some(@checked.Checked(_)),
    msg="the original numeric lowerer canonicalizes signed zero before checking",
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
let request_document_yaml : String =
  #|version: actql/0.1
  #|id: source-document
  #|params:
  #|  n: {type: number, default: 7}
  #|stages:
  #|  - id: main
  #|    inputs: {}
  #|    steps:
  #|      - values:
  #|          schema:
  #|            id: {type: number, nullable: false}
  #|            label: {type: string, nullable: false}
  #|          rows:
  #|            - {id: 1, label: "日本語😀"}
  #|        as: seed
  #|      - derive: {value: "id + $n"}
  #|        as: selected
  #|    results:
  #|      rows: {from: selected, fields: [id, label, value]}
  #|results:
  #|  answer: {from: {stage: main, result: rows}}

///|
test "normal Source document keeps original JSON YAML Parameters compiler Plan and Run" {
  let (environment, publication) = request_query_publication_fixture()
  for format in ["json", "aql-json", "yaml", "aql-yaml"] {
    let document = if format == "json" || format == "aql-json" {
      native_driver_program
    } else {
      request_document_yaml
    }
    let supplied = format != "aql-yaml"
    let (parent, input) = native_driver_parent(document)
    let source = request_document_test_source(document, format)
    assert_eq(
      prepare_request_native_source_computation(
        parent,
        input,
        source,
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
    let original = parent.held_program.unwrap()
    assert_true(parent.native_parameters_ready && parent.query_syntax is None)
    assert_true(
      if supplied {
        parent.native_parameters is Some(_)
      } else {
        parent.native_parameters is None
      },
    )
    let before = @resources.ledger_usage(parent.ledger)
    assert_true(
      prepare_request_native_source_computation(
        parent,
        input,
        source,
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
    assert_true(physical_equal(parent.held_program.unwrap(), original))
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
      "source-document",
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
test "Source document controls keep native supplied refusal before original parser" {
  let (environment, publication) = request_query_publication_fixture()
  for format in ["json", "yaml"] {
    let (parent, input) = native_driver_parent(
      "malformed document and supplied values",
    )
    assert_true(
      prepare_request_native_source_computation(
        parent,
        input,
        request_document_test_source("{", format),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
        supplied=Some(request_native_test_value("{\"é\":1,\"é\":2}")),
      )
      is Err(Preparation(Parameters(_))),
    )
    assert_true(parent.program_json is None && !parent.native_parameters_ready)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Source document controls preserve original JSON YAML parser refusals without fallback" {
  let (environment, publication) = request_query_publication_fixture()
  for (document, format) in [("{", "json"), ("id: &x forbidden", "yaml")] {
    let (parent, input) = native_driver_parent(document)
    assert_true(
      prepare_request_native_source_computation(
        parent,
        input,
        request_document_test_source(document, format),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
      )
      is Err(Preparation(ProgramJson(Syntax(Parse(_))))),
    )
    assert_true(
      parent.phase == ProgramJsonFailed && parent.program_json is None,
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Source document controls one short parse reservation refuses before malformed syntax" {
  let document = "{"
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  for retained in [true, false] {
    let (parent, input) = native_driver_parent(document)
    prepare_request_native_query_input(
      parent,
      input,
      native_json_reader,
      None,
      None,
    ).unwrap()
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let amount = request_document_parse_bytes(document, limits).unwrap()
    let policy = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retained {
        policy.retained_bytes - before.0 - amount + 1L
      } else {
        0L
      },
      if retained {
        0L
      } else {
        policy.execution_bytes - before.1 - amount + 1L
      },
    ).unwrap()
    assert_true(
      if retained {
        prepare_request_document_input(
          parent,
          input,
          document,
          @syntax.Json,
          limits,
        )
        is Err(Capacity(Resource(RetentionLimit)))
      } else {
        prepare_request_document_input(
          parent,
          input,
          document,
          @syntax.Yaml,
          limits,
        )
        is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(parent.program_json is None && parent.held_program is None)
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok(before),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Source document controls original parse and retained index growth fence reentry" {
  let input = [1]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let calls = Ref(0)
  let refused = Ref(0)
  let seen = Ref(false)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if armed.val {
        calls.val += 1
        let parent = selected.val.unwrap()
        if calls.val == 2 {
          seen.val = parent.program_json is Some(_)
        }
        if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
          refused.val += 1
        }
        if prepare_request_document_input(
            parent,
            input,
            native_driver_program,
            @syntax.Json,
            @publication_host.client_standard_program_preparation_limits().checking.input,
          )
          is Err(WrongPhase) {
          refused.val += 1
        }
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  selected.val = Some(parent)
  reserve_request_snapshot(parent, input, 100L, 100L).unwrap()
  prepare_request_native_query_input(
    parent,
    input,
    native_json_reader,
    None,
    None,
  ).unwrap()
  armed.val = true
  let child = prepare_request_document_input(
    parent,
    input,
    native_driver_program,
    @syntax.Json,
    @publication_host.client_standard_program_preparation_limits().checking.input,
  ).unwrap()
  armed.val = false
  assert_eq(calls.val, 2)
  assert_eq(refused.val, 4)
  assert_true(seen.val && child.phase == RetainedIndex)
  assert_true(physical_equal(child.capacity, parent.capacity))
  assert_true(physical_equal(child, parent.program_json.unwrap()))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(
    child.indexed is None && child.input is None && child.phase == Retired,
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Source document controls foreign input and current loss cannot enter parser or transfer index" {
  let input = [1]
  let armed = Ref(false)
  let calls = Ref(0)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if armed.val {
        calls.val += 1
        return false
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(parent, input, 100L, 100L).unwrap()
  prepare_request_native_query_input(
    parent,
    input,
    native_json_reader,
    None,
    None,
  ).unwrap()
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let before = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  armed.val = true
  assert_true(
    prepare_request_document_input(
      parent,
      [1],
      native_driver_program,
      @syntax.Json,
      limits,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(calls.val, 0)
  assert_true(
    prepare_request_document_input(
      parent,
      input,
      native_driver_program,
      @syntax.Yaml,
      limits,
    )
    is Err(Capacity(Resource(ClosedReservation))),
  )
  assert_eq(calls.val, 1)
  assert_true(parent.program_json is None && parent.phase == ProgramJsonFailed)
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok(before),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Source document Effect keeps original compiled branch Parameters and borrowed Plan input" {
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
    prepare_request_native_source_computation(
      parent,
      input,
      request_document_test_source(text, "yaml"),
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
extern "js" fn request_document_test_envelope(
  source : NativeJsonValue,
  parameters : NativeJsonValue,
) -> NativeJsonValue =
  #|(input,parameters) => ({kind:'aql',input,parameters,stopBefore:'commit',readOnly:true})

///|
test "Source document actual submitted intent keeps the same text format Parameters and options through compilation" {
  let (environment, publication) = request_query_publication_fixture()
  for format in ["json", "yaml"] {
    let document = if format == "json" {
      native_driver_program
    } else {
      request_document_yaml
    }
    let source = request_document_test_source(document, format)
    let parameters = request_native_test_value("{\"n\":9}")
    let (parent, input) = native_driver_parent(document)
    prepare_request_submitted_intent(
      parent,
      input,
      request_document_test_envelope(source, parameters),
      native_json_reader,
    ).unwrap()
    |> ignore
    let intent = request_submitted_intent_original(parent, input).unwrap()
    assert_true(
      @publication_host.client_submitted_intent_requests_commit_stop(intent),
    )
    assert_true(
      @publication_host.client_submitted_intent_requests_read_only(intent),
    )
    assert_true(
      @publication_host.client_submitted_intent_wire(intent).contains(
        "\"format\":\"" + format + "\"",
      ),
    )
    finish_request_submitted_intent(parent, input).unwrap()
    assert_eq(
      prepare_request_native_source_computation(
        parent,
        input,
        source,
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
        supplied=Some(parameters),
      ).unwrap(),
      Pure,
    )
    assert_true(
      physical_equal(
        request_submitted_intent_original(parent, input).unwrap(),
        intent,
      ),
    )
    assert_true(
      parent.native_parameters is Some(_) && parent.compiled_program is Some(_),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_true(request_submitted_intent_original(parent, input) is None)
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "configured Native query result keeps answer and public Source keeps main" {
  let (environment, publication) = request_query_publication_fixture()
  for (public_primary, expected) in [(false, "answer"), (true, "main")] {
    let document = "SELECT 2 AS id"
    let (parent, input) = native_driver_parent(document)
    // This is the SAME actual Query/Source/checker/compiler path selected by
    // Native. No result rename, authority override or replacement Run is used.
    prepare_request_native_source_computation(
      parent,
      input,
      request_document_test_source(document, "sql"),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
      public_primary~,
    ).unwrap()
    |> ignore
    let syntax = parent.query_syntax.unwrap()
    let artifact = prepare_request_program_compilation(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=false,
      provider_factory=_ => [],
    ).unwrap()
    let names = match artifact {
      @publication_host.Values(original) =>
        @publication_host.client_values_compilation_result_names(original)
      @publication_host.Tasks(original) =>
        @publication_host.client_task_compilation_result_names(original)
      _ => fail("Expected the same Pure compilation")
    }
    assert_eq(names, [expected])
    assert_true(physical_equal(parent.query_syntax.unwrap(), syntax))
    assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "configured Native query result preserves explicit Source exports" {
  let (environment, publication) = request_query_publication_fixture()
  for (public_primary, expected) in [(false, "chosen"), (true, "chosen")] {
    let document = "WITH seed AS (SELECT 2 AS id) FROM seed |> SELECT id |> RESULT chosen"
    let (parent, input) = native_driver_parent(document)
    // This is the SAME actual Query/Source/checker/compiler path selected by
    // Native. No result rename, authority override or replacement Run is used.
    prepare_request_native_source_computation(
      parent,
      input,
      request_document_test_source(document, "aql-text"),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
      public_primary~,
    ).unwrap()
    |> ignore
    let syntax = parent.query_syntax.unwrap()
    let artifact = prepare_request_program_compilation(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=false,
      provider_factory=_ => [],
    ).unwrap()
    let names = match artifact {
      @publication_host.Values(original) =>
        @publication_host.client_values_compilation_result_names(original)
      @publication_host.Tasks(original) =>
        @publication_host.client_task_compilation_result_names(original)
      _ => fail("Expected the same Pure compilation")
    }
    assert_eq(names, [expected])
    assert_true(physical_equal(parent.query_syntax.unwrap(), syntax))
    assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
extern "js" fn request_default_document_fixture(
  rows : Int,
  text_units : Int,
) -> String =
  #|(rows, textUnits) => JSON.stringify({version:'actql/0.1',id:'default-document',
  #| stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:{v0:{type:'number',nullable:false},label:{type:'string',nullable:false}},
  #| rows:Array.from({length:rows},(_,v0)=>({v0,label:'日😀\\\n'.repeat(Math.floor(textUnits/5))+'x'.repeat(textUnits%5)}))}}],
  #| results:{rows:{from:'v',fields:['v0','label']}}}],results:{answer0:{from:{stage:'main',result:'rows'}}}})

///|
fn default_document_parent(
  document : String,
  observed : Ref[Int],
) -> (ClientRequestPreparation[Array[Int]], Array[Int]) {
  let input = [1]
  let held : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if held.val is Some(parent) &&
        parent.program_json is Some(child) &&
        child.ready is Some(geometry) {
        observed.val = Int::max(observed.val, geometry.node_upper)
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  held.val = Some(parent)
  // Explicit outer-envelope fixture, not an SDK/physical capture claim. Its
  // original Text is one value, not one node per authored character. Actual
  // installed SDK capture/one-observer controls cover that separate boundary.
  reserve_request_snapshot(
    parent,
    input,
    document.length().to_int64() + 128L,
    12L,
  ).unwrap()
  (parent, input)
}

///|
test "default Source JSON observes actual nodes before the same Request parser and index" {
  // Use the actual default Local row projection. The generic Query fixture's
  // independent 1000-row Environment must still refuse larger Values input.
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
  for (rows, text) in [(10001, 0), (1, 100001)] {
    let document = request_default_document_fixture(rows, text)
    assert_true(document.length() > 65536)
    let observed = Ref(0)
    let (parent, input) = default_document_parent(document, observed)
    let result = prepare_request_default_source_computation_check(
      parent,
      input,
      request_document_test_source(document, "json"),
      native_json_reader,
      environment,
      publication,
      [],
      None,
      @publication_host.client_standard_effect_computation_limits(),
    )
    match result {
      Ok(_) => ()
      Err(Preparation(ProgramCheck(issue))) => {
        let stage = match issue {
          Capacity(inner) => "Capacity " + @debug.to_string(inner)
          Check(inner) =>
            match inner {
              Program(problem) => "Check Program " + @debug.to_string(problem)
              InvalidLimits => "Check InvalidLimits"
              CapacityInputs(_) => "Check CapacityInputs"
              Environment(_) => "Check Environment"
              Source(_) => "Check Source"
              Closure(_) => "Check Closure"
              Units(_) => "Check Units"
              Template(_, _) => "Check Template"
            }
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
        fail("default original document ProgramCheck: " + stage)
      }
      Err(CheckOutcome(@checked.Rejected(diagnostic))) => {
        let detail = match @checked.diagnostic_cause(diagnostic) {
          Program(problem) => "Program " + @debug.to_string(problem)
          Closure(Values(problem)) =>
            "Closure Values " + @debug.to_string(problem)
          Closure(BudgetExceeded) => "Closure BudgetExceeded"
          Closure(_) => "Closure"
          Source(Identity(_)) => "Source Identity"
          Source(_) => "Source"
          Units(BudgetExceeded) => "Units BudgetExceeded"
          Units(_) => "Units"
          Environment(_) => "Environment"
          CapacityInputs(_) => "CapacityInputs"
          InvalidLimits => "InvalidLimits"
          Template(_, _) => "Template"
        }
        fail(
          "default original diagnostic: " +
          @debug.to_string(@checked.diagnostic_category(diagnostic)) +
          " " +
          detail,
        )
      }
      Err(Preparation(issue)) =>
        fail(
          "default original document Preparation: " + @debug.to_string(issue),
        )
      Err(issue) => {
        let original : Error = issue
        fail("default original document failed: " + @debug.to_string(original))
      }
    }
    if rows > 1 {
      assert_true(observed.val > 8192)
    } else {
      // Few long Unicode/escaped values do not reserve their code units as
      // retained nodes. Source's original preflight supplied this observation.
      assert_true(observed.val > 0 && observed.val < 100)
      assert_true(observed.val < document.length() / 100)
    }
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "default Source JSON keeps malformed input current refusal and no parser fallback" {
  let (environment, publication) = request_query_publication_fixture()
  let document = "{"
  let observed = Ref(0)
  let (parent, input) = default_document_parent(document, observed)
  assert_true(
    prepare_request_default_source_computation_check(
      parent,
      input,
      request_document_test_source(document, "json"),
      native_json_reader,
      environment,
      publication,
      [],
      None,
      @publication_host.client_standard_effect_computation_limits(),
    )
    is Err(_),
  )
  assert_true(parent.program_json is Some(_))
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_default_source_computation_check(
      parent,
      input,
      request_document_test_source(document, "json"),
      native_json_reader,
      environment,
      publication,
      [],
      None,
      @publication_host.client_standard_effect_computation_limits(),
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "default Source JSON refuses current loss and short original budget before parser construction" {
  let (environment, publication) = request_query_publication_fixture()
  for shortage in [false, true] {
    let input = [1]
    let current = Ref(true)
    let parent = begin_request_preparation(
      request_parent_fixture(input, current=() => current.val),
      input,
      client_local_resource_policy(),
    ).unwrap()
    reserve_request_snapshot(parent, input, 100L, 12L).unwrap()
    let original_limits = @resources.ledger_limits(parent.ledger)
    let before = @resources.ledger_usage(parent.ledger)
    let blocker = if shortage {
      Some(
        @resources.reserve_capacity(
          parent.ledger,
          original_limits.retained_bytes - before.reserved_retention_bytes,
          original_limits.execution_bytes - before.reserved_execution_bytes,
        ).unwrap(),
      )
    } else {
      current.val = false
      None
    }
    let source = request_document_test_source("{", "json")
    assert_true(
      prepare_request_default_source_computation_check(
        parent,
        [1],
        source,
        native_json_reader,
        environment,
        publication,
        [],
        None,
        @publication_host.client_standard_effect_computation_limits(),
      )
      is Err(Preparation(ForeignOriginal)),
    )
    let result = prepare_request_default_source_computation_check(
      parent,
      input,
      source,
      native_json_reader,
      environment,
      publication,
      [],
      None,
      @publication_host.client_standard_effect_computation_limits(),
    )
    if shortage {
      assert_true(
        result
        is Err(Preparation(ProgramJson(Capacity(Resource(RetentionLimit))))),
      )
    } else {
      assert_true(
        result
        is Err(Preparation(ProgramJson(Capacity(Resource(ClosedReservation))))),
      )
    }
    assert_true(parent.program_json is None && parent.held_program is None)
    assert_eq(@resources.ledger_limits(parent.ledger), original_limits)
    if blocker is Some(original) {
      @resources.settle_capacity(parent.ledger, original).unwrap()
    }
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
extern "js" fn request_default_effect_document(base : String) -> String =
  #|(base) => {const p=JSON.parse(base),v=p.stages[0].steps[0].values;v.schema.label={type:'string',nullable:false};v.rows[0].label='日😀\\\n'.repeat(20001);return JSON.stringify(p);}

///|
test "default Source JSON carries the original input selection through Effect compilation" {
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
  let base =
    #|{"version":"actql/0.1","id":"native-effect","params":{"n":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"amount":"id + $n"},"as":"changed"}],"results":{"rows":{"from":"changed","fields":["id","amount"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"amount"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let text = request_default_effect_document(base)
  let observed = Ref(0)
  let (parent, input) = default_document_parent(text, observed)
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(text, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
    supplied=Some(request_native_test_value("{\"n\":9}")),
  ).unwrap()
  let source = parent.program_json.unwrap()
  assert_eq(parent.computation_limits.unwrap().checking.input, source.limits)
  assert_true(source.limits.tree.max_string_bytes > 65536)
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Effect,
  )
  assert_true(
    parent.compiled_effect is Some(_) && parent.compiled_program is None,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "actual default JSON numeric 100000 keeps its original Request resource cause" {
  // Use the actual default Local row projection. The generic Query fixture's
  // independent 1000-row Environment must still refuse larger Values input.
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
  let document = request_native_numeric_public_program(100000)
  let observed = Ref(0)
  let (parent, input) = default_document_parent(document, observed)
  let result = prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  )
  match result {
    Ok(_) => ()
    Err(Preparation(ProgramJson(Capacity(Resource(issue))))) => {
      let child = parent.program_json.unwrap()
      let phase = match child.phase {
        Preflight => "Preflight"
        Ready => "Ready"
        Indexed => "Indexed"
        RetainedIndex => "RetainedIndex"
        Inspected => "Inspected"
        Constructed => "Constructed"
        RetainedProgram => "RetainedProgram"
        Transferred => "Transferred"
        Failed => "Failed"
        Retired => "Retired"
      }
      let held = @resources.ledger_usage(parent.ledger)
      fail(
        "same original JSON100000 Resource " +
        @debug.to_string(issue) +
        "; phase=" +
        phase +
        "; baseR=" +
        child.base_retained.to_string() +
        "; baseE=" +
        child.base_execution.to_string() +
        "; heldR=" +
        held.reserved_retention_bytes.to_string() +
        "; heldE=" +
        held.reserved_execution_bytes.to_string() +
        "; nodesObserved=" +
        observed.val.to_string(),
      )
    }
    Err(_) => fail("same original JSON100000 changed typed failure family")
  }
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
