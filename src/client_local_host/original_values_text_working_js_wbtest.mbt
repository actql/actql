///|
extern "js" fn original_values_two_long_program() -> String =
  #|() => JSON.stringify({version:'actql/0.1',id:'few-long-strings',stages:[{id:'main',inputs:{},steps:[{as:'output',values:{schema:{id:{type:'number',nullable:false},text:{type:'string',nullable:false}},rows:[{id:0,text:{literal:'a'.repeat(524288)}},{id:1,text:{literal:'b'.repeat(524288)}}]}}],results:{rows:{from:'output',fields:['id','text']}}}],results:{answer0:{from:{stage:'main',result:'rows'}}}})

///|
test "original few long Values retain their complete text working demand" {
  let document = original_values_two_long_program()
  assert_true(document.length() > 1048576)
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  // Follow the actual Native intake/returned-intent handoff. No physical
  // Native Host, file descriptor or installed package is supplied here.
  reserve_request_native_intake_wire(
    parent,
    input,
    document.length() * 6 + 4096,
  ).unwrap()
  // Once selected, the actual managed Run owns this same parent's retirement.
  defer (if parent.phase != Selected && parent.phase != Selecting {
    abort_request_preparation_after_cleanup(parent).unwrap()
  })
  let (environment, publication) = request_query_publication_fixture()
  let writer = @encode.writer(document.length() * 6 + 1024, 4, 2)
  @encode.string_value(writer, document)
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"text\":" +
    @encode.finish(writer) +
    ",\"format\":\"json\"},\"parameters\":null}",
    document.length() * 6 + 1024,
    8192,
    64,
  ).unwrap()
  finish_request_native_intake_wire(parent, input, intent).unwrap()
  retain_request_submitted_intent(parent, input, intent).unwrap()
  reserve_request_retained_intent_source(parent, input).unwrap() |> ignore
  match
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
    ) {
    Ok(value) => value
    Err(Preparation(issue)) => fail("Preparation:" + @debug.to_string(issue))
    Err(CheckOutcome(_)) => fail("CheckOutcome")
    Err(Publication(_)) => fail("Publication")
    Err(QuerySyntax(_)) => fail("QuerySyntax")
    Err(QueryLowering(_)) => fail("QueryLowering")
  }
  let computation = finish_request_checked_computation(
    parent, input, environment, publication,
  ).unwrap()
  assert_eq(computation, ClientRequestComputationKind::Pure)
  let prepared = parent.compiled_program.unwrap()
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let requirements = prepare_source_free_local_requirements(
    prepared,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(
    requirements.capacity_plan.values.max_text_bytes >= 1048576,
    msg="the same two admitted original Values need their complete text extent",
  )
  let plan = requirements.capacity_plan
  let (text, wire, _) = client_local_original_values_text_bound(
    plan.sequences,
    plan.value_node_demand.unwrap(),
  ).unwrap()
  assert_eq(plan.values.max_text_bytes, text)
  assert_eq(plan.execution.rows.input_values.max_text_bytes, text)
  assert_eq(plan.execution.rows.output_values.max_text_bytes, text)
  assert_true(plan.measurement.max_bytes >= wire)
  assert_true(plan.imports.wire.max_bytes >= wire)
  assert_true(plan.imports.row.max_bytes >= Int::min(wire, 16777216))
  assert_true(plan.imports.row.max_bytes <= 16777216)
  assert_true(plan.imports.row.max_text_bytes >= text)
  assert_true(plan.imports.max_batch_bytes >= Int::min(wire, 16777216))
  assert_true(plan.exports.wire.max_bytes >= wire)
  assert_true(plan.exports.max_batch_bytes >= Int::min(wire, 16777216))
  assert_true(plan.exports.max_batch_bytes <= 16777216)
  assert_eq(plan.max_value_bytes, Int::max(10000, Int::min(wire, 16777216)))
  assert_true(
    client_local_original_values_text_bound(
      plan.sequences,
      plan.value_node_demand.unwrap(),
      max_work=0,
    )
    is None,
  )
  let original = source_free_installed_managed_preparation_owned(
    Pure(prepared),
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    false,
  ).unwrap()
  assert_eq(original.capacity_plan.values.max_text_bytes, text)
  assert_true(
    client_local_capacity_plan_matches(
      original.capacity_plan,
      original.sequences,
      @publication_host.prepared_client_values_max_rows(prepared),
    ),
  )
  assert_false(
    @syntax.program_preparation_data(parent.held_program.unwrap()).may_contain_expression_syntax,
  )
  match
    prepare_request_program_module_body(
      parent,
      input,
      installed,
      manifests=request_program_module_manifests(),
      compilation_limits=request_program_compilation_limits(parent, input).unwrap(),
      retained_output=false,
      provider_factory=_ => [],
    ) {
    Ok(_) => ()
    Err(Preparation(issue)) =>
      fail("ModulePreparation:" + @debug.to_string(issue))
    Err(Installed(Unsupported)) => fail("ModuleInstalled:Unsupported")
    Err(Installed(ForeignOriginal)) => fail("ModuleInstalled:ForeignOriginal")
    Err(Installed(_)) => fail("ModuleInstalled")
    Err(CapacityExceeded(_)) => fail("ModuleCapacityExceeded")
    Err(Construction(_)) => fail("ModuleConstruction")
    Err(ValuesCompilation(_)) => fail("ModuleValuesCompilation")
    Err(TaskCompilation(_)) => fail("ModuleTaskCompilation")
    Err(_) => fail("ModuleOther")
  }
  assert_true(parent.program_source_free.unwrap().configuration is Some(_))
  assert_eq(
    parent.program_source_free.unwrap().configuration.unwrap().capacity.max_value_bytes,
    plan.max_value_bytes,
  )
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-long-values",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  defer {
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      false,
    )
    .unwrap()
    .unwrap()
  let ledger = run.ledger.unwrap()
  assert_eq(@resources.ledger_limits(ledger).retained_bytes, 536870912L)
  assert_eq(@resources.ledger_limits(ledger).execution_bytes, 536870912L)
  let output = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(failure) => {
      let issue = local_values_execution_failure_issue(failure)
      assert_true(retry_local_values_execution_failure_cleanup(failure))
      fail(
        match issue {
          Driver(original) =>
            match original {
              Configuration(_) => "OriginalValuesExecution:Configuration"
              Preparation(_) => "OriginalValuesExecution:Preparation"
              Dispatch(_) => "OriginalValuesExecution:Dispatch"
              Execution(cause) =>
                match cause {
                  Compute(_) => "OriginalValuesExecution:Compute"
                  Physical(issue) =>
                    "OriginalValuesExecution:Physical:" +
                    @debug.to_string(issue)
                  Read(_) => "OriginalValuesExecution:Read"
                  Binding(_) => "OriginalValuesExecution:Binding"
                  Implementation(_) => "OriginalValuesExecution:Implementation"
                  _ => "OriginalValuesExecution:ExecutionOther"
                }
              Search(_) => "OriginalValuesExecution:Search"
              ManagedValues(Guard(ValueBytes(_, row, column))) =>
                "OriginalValuesExecution:ValueBytes:\{row}:\{column}"
              ManagedValues(Guard(Measurement(_, row, column, _))) =>
                "OriginalValuesExecution:Measurement:\{row}:\{column}"
              ManagedValues(Admission(issue)) =>
                "OriginalValuesExecution:Admission:" + @debug.to_string(issue)
              ManagedValues(_) => "OriginalValuesExecution:ManagedValuesOther"
              ManagedCopy(_) => "OriginalValuesExecution:ManagedCopy"
              ManagedRetention(_) => "OriginalValuesExecution:ManagedRetention"
              ManagedCompletion(_) =>
                "OriginalValuesExecution:ManagedCompletion"
              IdentityExport(_) => "OriginalValuesExecution:IdentityExport"
              CarrierSnapshot(_) => "OriginalValuesExecution:CarrierSnapshot"
            }
          Estimate(_) => "OriginalValuesExecution:Estimate"
          FinalizationLimit => "OriginalValuesExecution:FinalizationLimit"
          _ => "OriginalValuesExecution:Other"
        },
      )
    }
  }
  defer assert_true(output.close())
  let rows = output.rows().unwrap()
  assert_eq(rows.length(), 2)
  let mut seen_a = false
  let mut seen_b = false
  for row in rows {
    guard @json.parse(row) is Object(fields) &&
      fields.get("text") is Some(String(text)) else {
      fail("original complete Text result required")
    }
    if fields.get("id") == Some(Json::number(0)) {
      assert_false(seen_a)
      seen_a = true
      assert_eq(text, "a".repeat(524288))
    } else {
      assert_eq(fields.get("id"), Some(Json::number(1)))
      assert_false(seen_b)
      seen_b = true
      assert_eq(text, "b".repeat(524288))
    }
  }
  assert_true(seen_a && seen_b)
}

///|
// Same normal Request source/check/module/Run chain, with a supplied Parameter
// or an evaluated Text expression. No installed package or Native FFI is used.
fn original_bound_text_working_case(mode : Int) -> Unit raise {
  let parameter = mode == 0
  let (environment, publication) = request_query_publication_fixture()
  let document = if parameter {
    "{\"version\":\"actql/0.1\",\"id\":\"bound-text\",\"params\":{\"p\":{\"type\":\"string\"}},\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"v\",\"values\":{\"schema\":{\"text\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"text\":{\"$param\":\"p\"}}]}}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":[\"text\"]}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  } else if mode == 2 {
    original_cross_text_working_program()
  } else if mode == 3 {
    "SELECT REPEAT('x', 65537) AS text"
  } else {
    "SELECT REPEAT('x', 20000) AS text"
  }
  let supplied = if parameter {
    Some("{\"p\":\"" + "x".repeat(20000) + "\"}")
  } else {
    None
  }
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  // Original captured Source plus supplied map: fewer than512 structural
  // values; long Text units do not become nodes in this component's snapshot.
  let nodes = if mode == 2 { 4096L } else { 512L }
  reserve_request_snapshot(
    parent,
    input,
    document.length().to_int64() +
    supplied.map(s => s.length().to_int64()).unwrap_or(0L) +
    nodes,
    nodes,
  ).unwrap()
  defer (if parent.phase != Selected && parent.phase != Selecting {
    abort_request_preparation_after_cleanup(parent).unwrap()
  })
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(
      document,
      if parameter || mode == 2 {
        "json"
      } else {
        "sql"
      },
    ),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
    supplied=supplied.map(request_native_test_value),
  ).unwrap()
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    ClientRequestComputationKind::Pure,
  )
  let prepared = parent.compiled_program.unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests=request_program_module_manifests(),
    compilation_limits=request_program_compilation_limits(parent, input).unwrap(),
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  let configuration = parent.program_source_free.unwrap().configuration.unwrap()
  if mode == 2 {
    assert_true(configuration.capacity_plan.values.max_text_bytes >= 4095 * 512)
    assert_true(configuration.capacity_plan.imports.row.max_bytes <= 16777216)
    assert_true(configuration.capacity_plan.imports.max_batch_bytes <= 16777216)
  } else {
    assert_eq(configuration.capacity_plan.values.max_text_bytes, 500000)
    assert_eq(configuration.capacity_plan.imports.row.max_bytes, 65536)
    assert_eq(configuration.capacity_plan.imports.max_batch_bytes, 65536)
  }
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "bound-text",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let primary_failed = Ref(false)
  defer {
    let retired = retire_installed_managed_run(run) is Ok(_)
    if !primary_failed.val {
      assert_true(retired)
    }
    if retired {
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      false,
    )
    .unwrap()
    .unwrap()
  let output = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(failure) => {
      let issue = local_values_execution_failure_issue(failure)
      primary_failed.val = true
      let mut cleaned = false
      for _ in 0..<100000 {
        if retry_local_values_execution_failure_cleanup(failure) {
          cleaned = true
          break
        }
      }
      println("BOUND_TEXT_FAILURE mode=\{mode} cleanup=\{cleaned}")
      if mode == 3 {
        guard issue
          is Driver(Configuration(Execution(Rows(_, Evaluation(_, _, cause))))) else {
          fail(
            "selected row ceiling must remain an actual typed expression refusal",
          )
        }
        assert_eq(
          cause.kind,
          @execution.LogicalValue(
            @execution.ValueMeasure(@execution.WireMeasureFailure),
          ),
        )
        assert_true(cleaned)
        primary_failed.val = false
        return ()
      }
      fail(
        match issue {
          Driver(ManagedValues(Guard(ValueBytes(_, row, column)))) =>
            "BoundTextValueBytes:\{row}:\{column}"
          Driver(Configuration(Execution(Capture(step, cause)))) =>
            "BoundTextCapture:\{step}:" + @debug.to_string(cause)
          Driver(Execution(Physical(cause))) =>
            "BoundTextPhysical:" + @debug.to_string(cause)
          _ => "BoundTextExecutionFailed"
        },
      )
    }
  }
  assert_true(mode != 3, msg="out-of-profile Text must not publish an output")
  defer {
    let first = output.close()
    let mut closed = first
    for _ in 0..<100000 {
      if closed {
        break
      }
      closed = output.close()
    }
    println("BOUND_TEXT_CLOSE mode=\{mode} first=\{first} reclaimed=\{closed}")
    assert_true(closed, msg="same original bounded cleanup must finish")
    assert_true(first, msg="first original close must report actual cleanup")
  }
  let rows = output.rows().unwrap()
  assert_eq(rows.length(), if mode == 2 { 512 } else { 1 })
  let seen = Array::make(512, false)
  for row in rows {
    guard @json.parse(row) is Object(fields) else {
      fail("complete original row required")
    }
    guard fields.get("text") is Some(String(actual)) else {
      fail("original Text cell required")
    }
    assert_eq(
      actual,
      if mode == 2 {
        "expand:".repeat(585)
      } else {
        "x".repeat(20000)
      },
    )
    if mode == 2 {
      guard fields.get("copy") is Some(Number(value, ..)) else {
        fail("original copy key required")
      }
      let copy = value.to_int()
      assert_true(copy >= 0 && copy < 512)
      assert_eq(value, copy.to_double())
      assert_false(seen[copy])
      seen[copy] = true
    }
  }
  if mode == 2 {
    assert_true(seen.all(value => value))
  }
}

///|
test "ordinary bound Parameter Text uses its existing selected value policy" {
  original_bound_text_working_case(0)
}

///|
test "ordinary evaluated Text uses its existing selected value policy" {
  original_bound_text_working_case(1)
}

///|
extern "js" fn original_cross_text_working_program() -> String =
  #|() => JSON.stringify({version:'actql/0.1',id:'small-input-large-output',stages:[{id:'main',inputs:{},steps:[{as:'left_rows',values:{schema:{text:{type:'string',nullable:false}},rows:[{text:{literal:'expand:'.repeat(585)}}]}},{as:'right_rows',values:{schema:{copy:{type:'number',nullable:false}},rows:Array.from({length:512},(_,copy)=>({copy}))}},{as:'output',from:'left_rows',cross_join:{with:'right_rows',select:{text:'left.text',copy:'right.copy'}}}],results:{rows:{from:'output',fields:['text','copy']}}}],results:{answer0:{from:{stage:'main',result:'rows'}}}})

///|
test "ordinary expanded original Text retains full cross product output" {
  original_bound_text_working_case(2)
}

///|
test "ordinary evaluated Text still refuses its selected row value ceiling" {
  original_bound_text_working_case(3)
}

///|
test "copy Text envelope includes Unicode escapes and duplicate projected fields" {
  let payload = "😀é\n\"\\"
  let writer = @encode.writer(1024, 4, 2)
  @encode.string_value(writer, payload)
  let literal = @encode.finish(writer)
  let document = "{\"version\":\"actql/0.1\",\"id\":\"copy-proof\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"left\",\"values\":{\"schema\":{\"text\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"text\":{\"literal\":" +
    literal +
    "}}]}},{\"as\":\"right\",\"values\":{\"schema\":{\"copy\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"copy\":0},{\"copy\":1},{\"copy\":2}]}},{\"as\":\"out\",\"from\":\"left\",\"cross_join\":{\"with\":\"right\",\"select\":{\"text\":\"left.text\",\"again\":\"left.text\",\"copy\":\"right.copy\"}}}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"text\",\"again\",\"copy\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let prepared = single_source_free_capacity_prepared(document~)
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let requirements = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let plan = requirements.capacity_plan
  let (text, wire, row_wire) = client_local_original_values_text_bound(
    plan.sequences,
    plan.value_node_demand.unwrap(),
  ).unwrap()
  assert_true(text >= @utf8.encode(payload).length() * 3 * 2)
  assert_true(row_wire >= @utf8.encode(payload).length() * 2)
  assert_true(wire >= row_wire)
  assert_true(
    client_local_original_values_text_bound(
      plan.sequences,
      plan.value_node_demand.unwrap(),
      max_work=0,
    )
    is None,
  )
}
