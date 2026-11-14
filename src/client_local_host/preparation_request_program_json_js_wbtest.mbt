///|
// Authored prospective consumer tests against B's existing domain signatures.
// The original Node fixture owns only logical admission/current/cleanup; these
// are not SDK snapshot, Account, physical backing or ordinary Effect tests.
let request_json_effect_source : String =
  #|{"version":"actql/0.1","id":"request-json-é","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}

///|
test "original request parent continues into generic Unicode Effect source and Program on the same capacity" {
  let input = [1]
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let initial = request_parent_fixture(input)
  let parent = begin_request_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let entry = @execution.preparation_representation_cost(
    program_json_preparation_initial_inventory(),
  ).unwrap()
  let child = prepare_request_program_json_preparation(
    parent, input, request_json_effect_source, limits,
  ).unwrap()
  assert_true(physical_equal(child.capacity, parent.capacity))
  assert_true(physical_equal(child.limits, limits))
  assert_true(physical_equal(parent.program_json.unwrap(), child))
  assert_true(
    parent.initial is NodeRequestInitial(original) &&
    physical_equal(original, initial),
  )
  assert_true(parent.phase == ProgramJson)
  assert_eq(child.base_retained, before.reserved_retention_bytes)
  assert_eq(child.base_execution, before.reserved_execution_bytes)
  let after = @resources.ledger_usage(parent.ledger)
  // This is the original domain recipe once, never a second pre-added copy.
  assert_eq(
    after.reserved_retention_bytes,
    before.reserved_retention_bytes + entry,
  )
  assert_eq(
    after.reserved_execution_bytes,
    before.reserved_execution_bytes + entry,
  )
  let ready = Ref(false)
  for _ in 0..<(request_json_effect_source.length() + 1) {
    match advance_program_json_preparation(child, 64).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(_, ..) => {
        ready.val = true
        break
      }
      @source.JsonSourceFailed(_, ..) =>
        fail("original Effect JSON preflight refused")
    }
  }
  assert_true(ready.val)
  finish_program_json_preparation(child).unwrap()
  construct_program_json_preparation(child).unwrap()
  reconcile_program_json_preparation_structure(child).unwrap()
  assert_eq(child.program.unwrap().id, "request-json-é")
  assert_eq(@syntax.stage_count(child.program.unwrap()), 1)
  assert_true(physical_equal(child.capacity, parent.capacity))
  // No Program/output is transferred: the fixed consumer has finished using
  // these borrowed fields before its same original cleanup boundary.
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(child.phase == Retired && parent.phase == Closed)
  assert_true(parent.program_json is None)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_execution_bytes, 0L)
}

///|
test "request JSON caller refuses foreign and repeated originals before a second domain constructor" {
  let input = [1]
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_program_json_preparation(
      parent,
      [1],
      request_json_effect_source,
      limits,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  let child = prepare_request_program_json_preparation(
    parent, input, request_json_effect_source, limits,
  ).unwrap()
  let admitted = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_program_json_preparation(
      parent, input, request_json_effect_source, limits,
    )
    is Err(WrongPhase),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), admitted)
  assert_true(physical_equal(parent.program_json.unwrap(), child))
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "request JSON caller one-short domain grow keeps its original input and debit for cleanup" {
  let input = [1]
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let entry = @execution.preparation_representation_cost(
    program_json_preparation_initial_inventory(),
  ).unwrap()
  let sibling = @resources.reserve_capacity(
    parent.ledger,
    @resources.ledger_limits(parent.ledger).retained_bytes -
    before.reserved_retention_bytes -
    entry +
    1L,
    0L,
  ).unwrap()
  let held = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_program_json_preparation(
      parent, input, request_json_effect_source, limits,
    )
    is Err(
      ProgramJson(
        Capacity(
          @resources.PreparationCapacityIssue::Resource(
            @resources.LedgerIssue::RetentionLimit
          )
        )
      )
    ),
  )
  assert_true(parent.phase == ProgramJsonFailed && parent.program_json is None)
  assert_true(parent.input is Some(original) && physical_equal(original, input))
  assert_eq(@resources.ledger_usage(parent.ledger), held)
  @resources.settle_capacity(parent.ledger, sibling).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "request JSON caller keeps the same source while its actual domain consumer is busy" {
  let input = [1]
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let child = prepare_request_program_json_preparation(
    parent, input, request_json_effect_source, limits,
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  // Private component control models the existing domain's active quantum;
  // it is not a physical cleanup receipt or an independently issued reader.
  child.busy = true
  assert_true(
    abort_request_preparation_after_cleanup(parent)
    is Err(ProgramJson(WrongPhase)),
  )
  assert_true(parent.phase == ProgramJson)
  assert_true(physical_equal(parent.program_json.unwrap(), child))
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  child.busy = false
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "request bootstrap independently covers generic JSON entry allocated carriers before domain grow" {
  // The original 220H/402R/457W envelope adds four default-input limit
  // records and a Result wrapper (5H/7R/10W), plus the retired-scratch scalar (1W).
  // Observed intake adds ParseLimits/Some (2H/1R/3W) and the original
  // key-extent Ref/Some/Request field (2H/2R/1W):4H/3R/4W =120 bytes.
  // The retained-wire absolute quote tuple/Some and Request field add
  // 2H/2R/2W =64 bytes before any domain construction or growth.
  // The same Native intake baseline tuple/Some and Request slot add 2H/2R;
  // its two Int64 baselines plus monotone byte scalar add 3W =72 bytes.
  // Four original observation counters add 4W. The separately retained
  // source-free work selection adds its Some and scalar plus two reference
  // slots (1H/2R/1W =40 bytes), before any later module constructor.
  // Default generated-Query selection adds four records (4H/11R/14W).
  // Common observed input selections add3H/6R/13W =200 bytes.
  // The selected lexical-work Some/scalar and original holder reference add
  // 1H/1R/1W =32 bytes before the syntax grow.
  // The shared post-lowering returned selection adds1H/1R =24 bytes.
  // The existing 4096-byte entry group remains separate.
  // This independent tariff expansion includes no domain Source or Check body.
  let (retained, execution) = client_request_preparation_control_capacity(
    client_local_resource_policy(),
  ).unwrap()
  assert_eq(retained, 15560L)
  assert_eq(
    16L * (225L + 2L + 2L + 2L + 2L + 1L + 4L + 3L + 1L + 1L) +
    8L * (409L + 1L + 2L + 2L + 2L + 2L + 11L + 6L + 1L + 1L) +
    8L * (468L + 3L + 1L + 2L + 3L + 4L + 1L + 14L + 13L + 1L) +
    4096L,
    15560L,
  )
  assert_eq(16L * 4L + 8L * 3L + 8L * 4L, 120L)
  assert_eq(16L * 2L + 8L * 2L + 8L * 2L, 64L)
  assert_eq(16L * 2L + 8L * 2L + 8L * 3L, 72L)
  assert_eq(16L + 8L * 2L + 8L, 40L)
  assert_eq(execution, 0L)
  assert_eq(16L * 10L + 8L * 7L + 8L * 13L, 320L)
}

///|
test "original request bootstrap entry carriers are already debited at the sole domain current callback" {
  let input = [1]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let calls = Ref(0)
  let backed_before_resize = Ref(false)
  let initial = request_parent_fixture(input, current=() => {
    if armed.val {
      calls.val = calls.val + 1
      let parent = selected.val.unwrap()
      let usage = @resources.ledger_usage(parent.ledger)
      backed_before_resize.val = parent.phase == Selecting &&
        parent.program_json is None &&
        usage.reserved_retention_bytes == 15560L &&
        usage.reserved_execution_bytes == 0L
    }
    true
  })
  let parent = begin_request_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  selected.val = Some(parent)
  armed.val = true
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let child = prepare_request_program_json_preparation(
    parent, input, request_json_effect_source, limits,
  ).unwrap()
  armed.val = false
  assert_eq(calls.val, 1)
  assert_true(backed_before_resize.val)
  let usage = @resources.ledger_usage(parent.ledger)
  // Domain quote540H155R1153W +driver23H31R39W +stage5H7R4W
  // +preflight17H35R58W +observed-geometry/canonical return8H4R20W
  // +original SyntaxError alias/conservative Some1H2R2W (48 bytes)
  // =594H234R1276W=21584, once. It neither
  // replaces nor supplies the pre-entry carriers observed by that callback.
  assert_eq(
    16L * (585L + 8L + 1L) + 8L * (228L + 4L + 2L) + 8L * (1254L + 20L + 2L),
    21536L + 48L,
  )
  assert_eq(usage.reserved_retention_bytes, 15560L + 21536L + 48L)
  assert_eq(usage.reserved_execution_bytes, 21536L + 48L)
  assert_true(physical_equal(child.capacity, parent.capacity))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}
