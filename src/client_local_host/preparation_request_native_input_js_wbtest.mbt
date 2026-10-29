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
#cfg(target="js")
extern "js" fn request_native_test_value(document : String) -> NativeJsonValue =
  #|(document) => JSON.parse(document)

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
    reserve_request_snapshot(parent, input, units).unwrap()
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
      request_native_input_units(units, limits).unwrap(),
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
  reserve_request_snapshot(parent, input, 10L).unwrap()
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
  assert_true(request_native_input_units(67108864L, limits) is Some(_))
}
