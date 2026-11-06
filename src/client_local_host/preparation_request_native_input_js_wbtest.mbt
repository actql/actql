///|
/// Opaque native DATA, not an admitted Program or an SDK snapshot receipt.
/// The fixed Node caller retains the original SDK capture and Request parent.
#external
type NativeJsonValue

///|
extern "js" fn native_json_kind(value : NativeJsonValue) -> Int =
  #|(value) => value === null || typeof value === 'number' && !Number.isFinite(value) ? 0 : typeof value === 'boolean' ? 1 :
  #| typeof value === 'number' ? 2 : typeof value === 'string' ? 3 :
  #| Array.isArray(value) ? 4 : value !== null && typeof value === 'object' ? 5 : 6

///|
extern "js" fn native_json_bool(value : NativeJsonValue) -> Bool =
  #|(value) => value

///|
extern "js" fn native_json_text(value : NativeJsonValue) -> String =
  #|(value) => value

///|
extern "js" fn native_json_number_text(value : NativeJsonValue) -> String =
  #|(value) => String(value)

///|
extern "js" fn native_json_keys(value : NativeJsonValue) -> FixedArray[String] =
  #|(value) => Object.keys(value)

///|
extern "js" fn native_json_length(value : NativeJsonValue) -> Int =
  #|(value) => Object.getOwnPropertyDescriptor(value, 'length').value

///|
// Own DATA only: a malformed internal caller cannot invoke a getter while
// pretending to supply a detached native snapshot. The original SDK capture
// has plain dense arrays/objects; no second caller traversal is performed.
extern "js" fn native_json_field(
  value : NativeJsonValue,
  key : String,
) -> NativeJsonValue =
  #|(value, key) => {
  #| const field = Object.getOwnPropertyDescriptor(value, key);
  #| return field !== undefined && Object.hasOwn(field, 'value') ? field.value : undefined;
  #|}

///|
let native_json_reader : @source.JsonDataReader[NativeJsonValue] = {
  kind: native_json_kind,
  boolean: native_json_bool,
  text: native_json_text,
  number_text: native_json_number_text,
  keys: native_json_keys,
  length: native_json_length,
  field: native_json_field,
}

///|
// Exact authored public 100-column/99-row fixture, without a caller policy
// override or a serialization fallback in the production native entry.
extern "js" fn request_native_wide_public_program() -> String =
  #|() => {
  #| const fields = Array.from({length:100},(_,i)=>`v${i}`);
  #| const rows = Array.from({length:99},(_,r)=>Object.fromEntries(fields.map((name,c)=>[name,r+c])));
  #| return JSON.stringify({version:'actql/0.1',id:'static-limit-acceptance',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:Object.fromEntries(fields.map(name=>[name,{type:'number',nullable:false}])),rows}}],results:{rows:{from:'v',fields}}}],results:{answer0:{from:{stage:'main',result:'rows'}}}});
  #|}

///|
test "standard native Program input retains the original public 100 by 99 Values document" {
  let document = request_native_wide_public_program()
  assert_eq(document.length(), 98034)
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let admitted = @syntax.admit_captured_program_input(
    request_native_test_value(document), native_json_reader, limits,
  )
  assert_true(admitted is Ok(_))
}

///|
#cfg(target="js")
extern "js" fn request_native_test_value(document : String) -> NativeJsonValue =
  #|(document) => JSON.parse(document)

///|
// The authored SDK values fixture and its four original refusal mutations.
// This constructs test DATA only; the existing Request driver below performs
// the actual native admission, declaration and semantic-phase selection.
extern "js" fn request_native_presemantic_case(index : Int) -> String =
  #|(index) => {
  #| const program = {version:'actql/0.1', id:'client-values', stages:[{
  #|   id:'source', inputs:{}, steps:[{values:{schema:{id:{type:'number',nullable:false}},
  #|     rows:[{id:1},{id:2}]}, as:'selected'}],
  #|   results:{rows:{from:'selected',fields:['id']}}}],
  #|   results:{answer:{from:{stage:'source',result:'rows'}}}};
  #| if (index === 0) program.bindings = {opaque:{type:'string'}};
  #| else if (index === 1) program.stages = Array.from({length:33}, (_,i) =>
  #|   ({...program.stages[0], id:`stage-${i}`}));
  #| else if (index === 2) program['e\u0301/😀~'] = null;
  #| else if (index === 3) program.params = {n:{type:'number',default:'private-default'}};
  #| else throw new Error('Unknown authored refusal case');
  #| return JSON.stringify(program);
  #|}

///|
test "native submission preparation refusals have no original semantic observation" {
  let (environment, publication) = request_query_publication_fixture()
  for index in 0..<4 {
    let text = request_native_presemantic_case(index)
    let (parent, input) = native_driver_parent(text)
    let terminal = match
      prepare_request_native_computation_check(
        parent,
        input,
        request_native_test_value(text),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
      ) {
      Err(issue) => issue
      Ok(_) => fail("the authored refusal was accepted: " + index.to_string())
    }
    guard terminal is Preparation(_) else {
      fail("the original semantic checker was reached: " + index.to_string())
    }
    assert_true(
      parent.compiled_program is None && parent.compiled_effect is None,
    )
    let before = @resources.ledger_usage(parent.ledger)
    // An absent original cannot supply a report, location or verdict. Even a
    // malformed audience body must not invoke a replacement projection.
    assert_true(
      request_observation_project(parent, input, terminal, "malformed")
      is Ok(None),
    )
    assert_eq(@resources.ledger_usage(parent.ledger), before)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Request native input reaches the existing Program and original checker on one capacity" {
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
  let limits = @publication_host.client_standard_program_preparation_limits().checking
  // This component supplies the original SDK traversal's conservative units;
  // the actual SDK/Host snapshot closure is qualified by its separate tests.
  reserve_request_snapshot(
    parent,
    input,
    request_check_wire.length().to_int64(),
    request_check_wire.length().to_int64(),
  ).unwrap()
  let before = calls.val
  let source = prepare_request_native_program_input(
    parent,
    input,
    request_native_test_value(request_check_wire),
    native_json_reader,
    limits.input,
  ).unwrap()
  assert_eq(calls.val - before, 1)
  assert_true(physical_equal(source.capacity, parent.capacity))
  let original_index = source.indexed.unwrap()
  assert_true(
    prepare_request_native_program_input(
      parent,
      input,
      request_native_test_value(request_check_wire),
      native_json_reader,
      limits.input,
    )
    is Err(WrongPhase),
  )
  assert_eq(calls.val - before, 1)
  construct_program_json_preparation(source).unwrap()
  reconcile_program_json_preparation_structure(source).unwrap()
  assert_true(physical_equal(source.indexed.unwrap(), original_index))
  let program = source.program.unwrap()
  let child = prepare_request_program_check_preparation(
    parent,
    input,
    catalog_domain_environment(),
    None,
    [],
    limits,
  ).unwrap()
  assert_true(physical_equal(child.arguments.unwrap().program, program))
  assert_true(physical_equal(child.capacity, parent.capacity))
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
  guard finish_program_check_preparation(child).unwrap()
    is @checked.Checked(checked) else {
    fail("the same native Program must complete its existing checker")
  }
  assert_true(physical_equal(@checked.checked_source_program(checked), program))
  let consumed = @resources.ledger_usage(parent.ledger)
  abort_request_preparation_after_cleanup(parent).unwrap()
  let closed = @resources.ledger_usage(parent.ledger)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  assert_eq(closed.planning_work, consumed.planning_work)
}

///|
test "Request native input short grows reentry and typed refusal retain the original cleanup duty" {
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  for retention in [true, false] {
    let input = [1]
    let action : Ref[(() -> Unit)?] = Ref(None)
    let fenced = Ref(false)
    let parent = begin_request_preparation(
      request_parent_fixture(input, current=() => {
        if action.val is Some(run) {
          run()
        }
        true
      }),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let units = request_check_wire.length().to_int64()
    reserve_request_snapshot(parent, input, units, units).unwrap()
    let original = request_native_test_value(request_check_wire)
    let before = @resources.ledger_usage(parent.ledger)
    assert_true(
      prepare_request_native_program_input(
        parent,
        [1],
        original,
        native_json_reader,
        limits,
      )
      is Err(ForeignOriginal),
    )
    assert_eq(@resources.ledger_usage(parent.ledger), before)
    let quote = @execution.preparation_representation_cost(
      request_native_input_units(units, units, limits).unwrap(),
    ).unwrap()
    let capacity = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        capacity.retained_bytes - before.reserved_retention_bytes - quote + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        capacity.execution_bytes - before.reserved_execution_bytes - quote + 1L
      },
    ).unwrap()
    action.val = Some(() => {
      fenced.val = prepare_request_native_program_input(
          parent, input, original, native_json_reader, limits,
        )
        is Err(WrongPhase) &&
        abort_request_preparation_after_cleanup(parent) is Err(WrongPhase)
    })
    let held = @resources.ledger_usage(parent.ledger)
    assert_true(
      prepare_request_native_program_input(
        parent, input, original, native_json_reader, limits,
      )
      is Err(Capacity(_)),
    )
    action.val = None
    assert_true(
      fenced.val &&
      parent.phase == ProgramJsonFailed &&
      parent.program_json is None,
    )
    assert_eq(@resources.ledger_usage(parent.ledger), held)
    assert_true(
      prepare_request_native_program_input(
        parent, input, original, native_json_reader, limits,
      )
      is Err(WrongPhase),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(parent, input, 10L, 10L).unwrap()
  assert_true(
    prepare_request_native_program_input(
      parent,
      input,
      request_native_test_value("{\"stages\":[]}"),
      native_json_reader,
      { ..limits, tree: { ..limits.tree, max_nodes: 0, }, },
    )
    is Err(ProgramJson(Syntax(Decode(_)))),
  )
  assert_true(parent.phase == ProgramJsonFailed)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request native input quote keeps the existing Int source range before bounding wire bytes" {
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  // This only prices DATA. No large object, wire, tree or reservation is built.
  assert_true(request_native_input_units(67108864L, 3L, limits) is Some(_))
}

///|
test "Request captured Parameters keep their original cursor through binding compiler Plan and Run retirement" {
  let document =
    #|{"version":"actql/0.1","id":"native-parameter","params":{"n":{"type":"number"}},"stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"value":"id + $n"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let limits = @publication_host.client_standard_program_preparation_limits()
  reserve_request_snapshot(parent, input, 2048L, 512L).unwrap()
  let source = prepare_request_native_program_input(
    parent,
    input,
    request_native_test_value(document),
    native_json_reader,
    limits.checking.input,
    supplied=Some(request_native_test_value("{\"n\":7}")),
  ).unwrap()
  let original = parent.native_parameters.unwrap()
  assert_eq(
    @decode.finite_number(
      @decode.required(@decode.open_object(original).unwrap(), "n").unwrap(),
    ).unwrap(),
    7.0,
  )
  construct_program_json_preparation(source).unwrap()
  reconcile_program_json_preparation_structure(source).unwrap()
  let program = source.program.unwrap()
  let foreign = @local_preparation.admit_captured_local_parameters(
    request_native_test_value("{\"n\":7}"),
    native_json_reader,
  ).unwrap()
  assert_true(
    prepare_request_program_check_preparation(
      parent,
      input,
      catalog_domain_environment(),
      Some(foreign),
      [],
      limits.checking,
    )
    is Err(ForeignOriginal),
  )
  assert_true(source.phase == RetainedProgram)
  let child = prepare_request_program_check_preparation(
    parent,
    input,
    catalog_domain_environment(),
    None,
    [],
    limits.checking,
  ).unwrap()
  assert_true(
    physical_equal(child.arguments.unwrap().supplied.unwrap(), original),
  )
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
  guard finish_program_check_preparation(child).unwrap()
    is @checked.Checked(checked) else {
    fail("the original captured Parameters must bind in the ordinary checker")
  }
  assert_true(physical_equal(@checked.checked_source_program(checked), program))
  let prepared = compile_program_check_preparation(child, limits).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  reserve_request_program_plan(parent, input).unwrap()
  complete_request_program_preparation(
    parent,
    input,
    request_program_installed_plan(prepared),
  ).unwrap()
  let holder = borrow_request_program_preparation(parent).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-native-parameter-request",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(
    parent.native_parameters is None && !parent.native_parameters_ready,
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_execution_bytes, 0L)
}

///|
test "Request captured Parameters preserve original key limits and typed precedence before invalid Program" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  reserve_request_snapshot(parent, input, 1024L, 32L).unwrap()
  assert_true(
    prepare_request_native_program_input(
      parent,
      input,
      request_native_test_value("{}"),
      native_json_reader,
      limits,
      supplied=Some(request_native_test_value("{\"é\":1,\"é\":2}")),
    )
    is Err(
      Parameters(
        @local_preparation.SuppliedSyntax(
          { issue: @source.DuplicateKey("é"), .. }
        )
      )
    ),
  )
  assert_true(parent.program_json is None && parent.phase == ProgramJsonFailed)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  let (source_limits, tree_limits) = @local_preparation.local_parameter_input_limits()
  assert_eq(
    (
      source_limits.max_input_bytes,
      source_limits.max_nodes,
      source_limits.max_depth,
    ),
    (65536, 8192, 64),
  )
  assert_eq(
    (
      tree_limits.max_nodes,
      tree_limits.max_depth,
      tree_limits.max_string_bytes,
      tree_limits.max_total_string_bytes,
    ),
    (8192, 64, 65536, 65536),
  )
}

///|
test "Request observed shape grows independently of Text without duplicate current calls" {
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
  let before = calls.val
  reserve_request_snapshot(parent, input, 65536L, 16L).unwrap()
  let actual = @resources.ledger_usage(parent.ledger)
  reserve_request_snapshot(parent, input, 65536L, 16L).unwrap()
  assert_eq(calls.val - before, 1)
  reserve_request_snapshot(parent, input, 65536L, 32L).unwrap()
  assert_eq(calls.val - before, 2)
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes >
    actual.reserved_retention_bytes,
  )
  assert_eq(parent.snapshot_units, 65536L)
  assert_eq(parent.snapshot_values, 32L)
  assert_true(
    reserve_request_snapshot(parent, input, 65536L, 16L) is Err(Policy),
  )
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let separate = request_native_input_units(65536L, 32L, limits).unwrap()
  let coupled = request_native_input_units(65536L, 65536L, limits).unwrap()
  assert_true(separate.reference_slots < coupled.reference_slots)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "refused original Query keeps an independent supplied type violation without a second check" {
  let text = "SELECT missing AS n FROM records WHERE amount >= @minimum"
  let declarations = "{\"minimum\":{\"type\":\"number\"}}"
  let parameters = "{\"minimum\":\"twenty\"}"
  let captured = "{\"format\":\"sql\",\"text\":\"" +
    text +
    "\",\"parameterDeclarations\":" +
    declarations +
    "}"
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(captured + parameters)
  let terminal = match
    prepare_request_native_source_computation_check(
      parent,
      input,
      request_native_test_value(captured),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
      supplied=Some(request_native_test_value(parameters)),
    ) {
    Err(issue) => issue
    Ok(_) => fail("the unpublished Source must not be accepted")
  }
  let query = parent.query_syntax.unwrap()
  let original_query = query.query.unwrap().unwrap()
  let lowering = query.lowering.unwrap()
  let original_failure = lowering.output.unwrap()
  assert_true(
    parent.phase == QueryLoweringFailed && parent.program_check is None,
  )
  let before = @resources.ledger_usage(parent.ledger)
  let project = () => {
    project_request_check_outcome(
      parent,
      input,
      terminal,
      "{\"environmentCid\":\"" +
      @checked.checking_environment_cid(environment) +
      "\",\"aliases\":[]}",
      "ctx:" + "a".repeat(64),
      "text",
      "rev:" + "b".repeat(64),
      text.length(),
      Some("rev:" + "d".repeat(64)),
      declarations.length(),
      Some("rev:" + "e".repeat(64)),
      parameters.length(),
      "corr:" + "c".repeat(32),
      None,
    )
    .unwrap()
    .unwrap()
  }
  let report = project()
  assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
  assert_true(report.contains("supplied_value_type_mismatch"), msg=report)
  assert_true(report.contains("\"parameter\":\"minimum\""), msg=report)
  assert_true(report.contains("\"expected_type\":\"number\""), msg=report)
  assert_true(report.contains("\"actual_type\":\"string\""), msg=report)
  assert_true(report.contains("source_resolution"), msg=report)
  assert_true(!report.contains("twenty"), msg=report)
  assert_eq(project(), report)
  let original_supplied = parent.native_parameters
  parent.native_parameters = Some(
    @local_preparation.admit_captured_local_parameters(
      request_native_test_value(parameters),
      native_json_reader,
    ).unwrap(),
  )
  assert_true(
    project_request_check_outcome(
      parent,
      input,
      terminal,
      "{\"environmentCid\":\"" +
      @checked.checking_environment_cid(environment) +
      "\",\"aliases\":[]}",
      "ctx:" + "a".repeat(64),
      "text",
      "rev:" + "b".repeat(64),
      text.length(),
      Some("rev:" + "d".repeat(64)),
      declarations.length(),
      Some("rev:" + "e".repeat(64)),
      parameters.length(),
      "corr:" + "c".repeat(32),
      None,
    )
    is Err(ForeignOriginal),
  )
  parent.native_parameters = original_supplied
  assert_true(
    parent.phase == QueryLoweringFailed && parent.program_check is None,
  )
  assert_true(physical_equal(query.query.unwrap().unwrap(), original_query))
  assert_true(physical_equal(lowering.output.unwrap(), original_failure))
  assert_eq(
    @resources.ledger_usage(parent.ledger).planning_work,
    before.planning_work,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
extern "js" fn query_refusal_test_throw_undefined() -> Bool =
  #|() => { throw undefined; }

///|
extern "js" fn query_refusal_test_is_undefined(
  failure : QueryBindingForeignFailure,
) -> Bool =
  #|failure => Object.hasOwn(failure, 'cause') && failure.cause === undefined

///|
test "refused Query binding retains the original failure and pending work on short capacity or undefined current" {
  for throw_undefined in [false, true] {
    let text = "SELECT missing AS n FROM records WHERE amount >= @minimum"
    let declarations = "{\"minimum\":{\"type\":\"number\"}}"
    let parameters = "{\"minimum\":\"twenty\"}"
    let captured = "{\"format\":\"sql\",\"text\":\"" +
      text +
      "\",\"parameterDeclarations\":" +
      declarations +
      "}"
    let (environment, publication) = request_query_publication_fixture()
    let input = [1]
    let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
    let triggered = Ref(false)
    let blocker = Ref(None)
    let initial = request_parent_fixture(input, current=() => {
      if !triggered.val &&
        selected.val is Some(parent) &&
        parent.query_syntax is Some(query) &&
        query.lowering is Some(lowering) &&
        lowering.refusal_binding is Some(binding) &&
        binding.work is Some(_) {
        triggered.val = true
        if throw_undefined {
          return query_refusal_test_throw_undefined()
        }
        let limits = @resources.ledger_limits(parent.ledger)
        let usage = @resources.ledger_usage(parent.ledger)
        blocker.val = Some(
          @resources.reserve_capacity(
            parent.ledger,
            limits.retained_bytes - usage.reserved_retention_bytes,
            0L,
          ).unwrap(),
        )
      }
      true
    })
    let parent = begin_request_preparation(
      initial,
      input,
      client_local_resource_policy(),
    ).unwrap()
    selected.val = Some(parent)
    reserve_request_snapshot(parent, input, 1024L, 256L).unwrap()
    let terminal = match
      prepare_request_native_source_computation_check(
        parent,
        input,
        request_native_test_value(captured),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
        supplied=Some(request_native_test_value(parameters)),
      ) {
      Err(issue) => issue
      Ok(_) => fail("the original lowerer must still refuse")
    }
    assert_true(triggered.val)
    let query = parent.query_syntax.unwrap()
    let lowering = query.lowering.unwrap()
    let binding = lowering.refusal_binding.unwrap()
    let original_failure = match lowering.output.unwrap() {
      Err(issue) => issue
      Ok(_) => fail("the original lowering failure must remain")
    }
    assert_true(
      parent.phase == QueryLoweringFailed && parent.program_check is None,
    )
    assert_true(
      @parameters.binding_read_phase(binding.reader) ==
      @parameters.BindingHeader,
    )
    assert_true(binding.work is Some(_) && binding.returned)
    if throw_undefined {
      // The actual ordinary original catches a failed current and latches
      // retirement. Preserve its existing typed refusal, not a fabricated ACK.
      guard terminal
        is QueryLowering(
          BindingFailure(original, Capacity(Resource(ClosedReservation)))
        ) else {
        fail("lost current must retain the original typed capacity refusal")
      }
      assert_true(physical_equal(original, original_failure))
    } else {
      guard terminal is QueryLowering(BindingFailure(original, Capacity(_))) else {
        fail("short reservation must not become a supplied-value refusal")
      }
      assert_true(physical_equal(original, original_failure))
      @resources.settle_capacity(parent.ledger, blocker.val.unwrap()).unwrap()
    }
    assert_true(
      lower_request_published_query(
        parent,
        input,
        publication,
        environment,
        None,
        public_primary=true,
        binding_limits=Some(
          request_query_binding_limits(
            @publication_host.client_standard_program_preparation_limits().checking,
          ),
        ),
      )
      is Err(Request(WrongPhase)),
    )
    assert_true(
      physical_equal(lowering.refusal_binding.unwrap().reader, binding.reader),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_true(binding.work is None)
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "refused Query binding foreign boundary retains undefined as a present failure" {
  let finished = Ref(0)
  let result : Result[
    Result[Unit, ClientRequestPreparationIssue],
    QueryBindingForeignFailure,
  ] = query_binding_protected_call(
    () => {
      query_refusal_test_throw_undefined() |> ignore
      Ok(())
    },
    () => finished.val += 1,
  )
  guard result is Err(original) else {
    fail("undefined must remain a present foreign failure")
  }
  assert_true(query_refusal_test_is_undefined(original))
  assert_eq(finished.val, 1)
}

///|
fn query_pointer_original_fixture(
  raw : String,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  ClientRequestTerminalIssue,
  String,
  String,
  String,
  String,
) raise {
  let name = if raw == "minimum" { "minimum" } else { "K" }
  let text = "SELECT missing AS n FROM records WHERE amount >= @" + name
  let declarations = "{\"" + name + "\":{\"type\":\"number\"}}"
  let parameters = "{\"" + raw + "\":\"caller-private\"}"
  let captured = "{\"format\":\"sql\",\"text\":\"" +
    text +
    "\",\"parameterDeclarations\":" +
    declarations +
    "}"
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(captured + parameters)
  let terminal = match
    prepare_request_native_source_computation_check(
      parent,
      input,
      request_native_test_value(captured),
      native_json_reader,
      environment,
      publication,
      [],
      @publication_host.client_standard_program_preparation_limits(),
      @publication_host.client_standard_effect_computation_limits(),
      supplied=Some(request_native_test_value(parameters)),
    ) {
    Err(issue) => issue
    Ok(_) => fail("the protected original Source must remain a refusal")
  }
  guard terminal is QueryLowering(WithBinding(_, _)) else {
    fail("only the completed original binding supplies this finding")
  }
  let visible = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  (parent, input, terminal, text, declarations, parameters, visible)
}

///|
fn query_pointer_original_report(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  terminal : ClientRequestTerminalIssue,
  text : String,
  declarations : String,
  parameters : String,
  visible : String,
  body : String?,
) -> Result[String?, ClientRequestPreparationIssue] {
  project_request_check_outcome(
    parent,
    input,
    terminal,
    visible,
    "ctx:" + "a".repeat(64),
    "text",
    "rev:" + "b".repeat(64),
    @utf8.encode(text).length(),
    Some("rev:" + "d".repeat(64)),
    @utf8.encode(declarations).length(),
    Some("rev:" + "e".repeat(64)),
    @utf8.encode(parameters).length(),
    "corr:" + "c".repeat(32),
    None,
    original_parameters=body,
  )
}

///|
test "refused original Query locations require matching raw supplied keys and current originals" {
  for raw in ["minimum", "K", "\u{212a}"] {
    let (parent, input, terminal, text, declarations, parameters, visible) = query_pointer_original_fixture(
      raw,
    )
    let query = parent.query_syntax.unwrap()
    let lowering = query.lowering.unwrap()
    let original_failure = lowering.output.unwrap()
    let binding = lowering.refusal_binding.unwrap()
    let work = @resources.ledger_usage(parent.ledger).planning_work
    let project = (body : String?) => {
      query_pointer_original_report(
        parent, input, terminal, text, declarations, parameters, visible, body,
      )
    }
    let absent = project(None).unwrap().unwrap()
    assert_true(absent.contains("supplied_value_type_mismatch"))
    assert_false(absent.contains("\"pointer\":"))
    let present = project(Some(parameters)).unwrap().unwrap()
    assert_true(present.contains("\"pointer\":\"/" + raw + "\""), msg=present)
    assert_true(present.contains("unresolved_protected"), msg=present)
    assert_false(present.contains("caller-private"))
    assert_false(present.contains("\"parameter\":\"missing\""))
    // A moved key and malformed scalar spelling cannot acquire a location.
    for body in ["{\"Z\":\"caller-private\"}", "{\""] {
      let moved = project(Some(body)).unwrap().unwrap()
      assert_true(moved.contains("supplied_value_type_mismatch"))
      assert_false(moved.contains("\"pointer\":"), msg=moved)
    }
    assert_true(
      project(Some(parameters + " ".repeat(16))) is Err(ForeignOriginal),
    )
    let supplied = parent.native_parameters
    parent.native_parameters = Some(
      @local_preparation.admit_captured_local_parameters(
        request_native_test_value(parameters),
        native_json_reader,
      ).unwrap(),
    )
    assert_true(project(Some(parameters)) is Err(ForeignOriginal))
    parent.native_parameters = supplied
    assert_true(physical_equal(lowering.output.unwrap(), original_failure))
    assert_true(physical_equal(lowering.refusal_binding.unwrap(), binding))
    assert_true(parent.phase == QueryLoweringFailed)
    assert_eq(@resources.ledger_usage(parent.ledger).planning_work, work)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_true(project(Some(parameters)).unwrap() is None)
  }
}

///|
test "refused Query raw pointer workspace cannot borrow a one-short reservation" {
  let (parent, input, terminal, text, declarations, parameters, visible) = query_pointer_original_fixture(
    "minimum",
  )
  let project = (body : String?) => {
    query_pointer_original_report(
      parent, input, terminal, text, declarations, parameters, visible, body,
    )
  }
  let _ = project(None).unwrap().unwrap()
  let query = parent.query_syntax.unwrap()
  let lowering = query.lowering.unwrap()
  let binding = lowering.refusal_binding.unwrap()
  let original = lowering.output.unwrap()
  let (declaration_root, declared) = parent.native_query_declarations.unwrap()
  let units = text.length().to_int64() +
    @decode.admission_usage(declaration_root).nodes.to_int64() +
    1L
  let findings = 2L * @parameters.declaration_count(declared).to_int64() + 4L
  let report_bytes = request_check_observation_inventory_bytes(
    visible, findings, units,
  ).unwrap()
  let pointer_bytes = request_check_original_pointer_bytes(
    parameters,
    parent.native_parameters.unwrap(),
  ).unwrap()
  let (retained, _) = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let policy = @resources.ledger_limits(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    policy.retained_bytes - retained - report_bytes - pointer_bytes + 1L,
    0L,
  ).unwrap()
  let work = @resources.ledger_usage(parent.ledger).planning_work
  assert_true(project(Some(parameters)) is Err(Capacity(_)))
  assert_true(parent.phase == QueryLoweringFailed)
  assert_true(physical_equal(lowering.output.unwrap(), original))
  assert_true(physical_equal(lowering.refusal_binding.unwrap(), binding))
  assert_eq(@resources.ledger_usage(parent.ledger).planning_work, work)
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  let report = project(Some(parameters)).unwrap().unwrap()
  assert_true(report.contains("\"pointer\":\"/minimum\""), msg=report)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "refused Query reports original missing declarations beside an independent wrong value" {
  let text = "SELECT @a AS n, @b AS m FROM records"
  let declarations = "{\"a\":{\"type\":\"number\"},\"b\":{\"type\":\"number\"}}"
  let captured = "{\"format\":\"sql\",\"text\":\"" +
    text +
    "\",\"parameterDeclarations\":" +
    declarations +
    "}"
  for (missing, wrong) in [("a", "b"), ("b", "a")] {
    let parameters = "{\"" + wrong + "\":\"caller-private\"}"
    let (environment, publication) = request_query_publication_fixture()
    let (parent, input) = native_driver_parent(captured + parameters)
    let terminal = match
      prepare_request_native_source_computation_check(
        parent,
        input,
        request_native_test_value(captured),
        native_json_reader,
        environment,
        publication,
        [],
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
        supplied=Some(request_native_test_value(parameters)),
      ) {
      Err(issue) => issue
      Ok(_) => fail("the unavailable original Source remains a refusal")
    }
    guard terminal is QueryLowering(WithBinding(_, _)) else {
      fail("the same complete binding must retain its wrong-value finding")
    }
    let original = parent.query_syntax.unwrap().lowering.unwrap()
    let reader = original.refusal_binding.unwrap().reader
    let failure = original.output.unwrap()
    let work = @resources.ledger_usage(parent.ledger).planning_work
    let report = query_pointer_original_report(
        parent,
        input,
        terminal,
        text,
        declarations,
        parameters,
        "{\"environmentCid\":\"" +
        @checked.checking_environment_cid(environment) +
        "\",\"aliases\":[]}",
        Some(parameters),
      )
      .unwrap()
      .unwrap()
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(report.contains("supplied_value_type_mismatch"), msg=report)
    assert_true(report.contains("\"pointer\":\"/" + wrong + "\""), msg=report)
    assert_true(report.contains("parameter_value_required"), msg=report)
    assert_true(
      report.contains("\"parameter\":\"" + missing + "\""),
      msg=report,
    )
    assert_true(report.contains("bound_values_missing"), msg=report)
    assert_true(report.contains("unresolved_protected"), msg=report)
    assert_false(report.contains("caller-private"))
    assert_true(
      physical_equal(original.refusal_binding.unwrap().reader, reader),
    )
    assert_true(physical_equal(original.output.unwrap(), failure))
    assert_eq(@resources.ledger_usage(parent.ledger).planning_work, work)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
