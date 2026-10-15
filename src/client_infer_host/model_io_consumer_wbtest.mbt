///|
// Actual original read/Run/Model/Entry/Ledger, with explicitly synthetic
// physical IO and Store-settlement ACKs. No installed-port or numeric grant.
fn original_io_consumer_fixture(
  calls : Ref[Int],
  ready : Ref[Bool],
  io_closed : Ref[Bool],
  release : Ref[Bool],
  terminal? : @model.ModelPhysicalCallPoll = @model.PhysicalResponse(
    async_response_observation(None),
  ),
  cleanup_calls? : Array[Bool] = [],
  polls? : Ref[Int] = Ref(0),
  per_slot? : ((Int) -> @model.ModelPhysicalCallPoll)? = None,
  current? : Ref[@authorization.AdmittedAccountConfiguration] = Ref(
    evidence_account(@authorization.Allow),
  ),
) -> (
  Execution,
  Int64,
  @resources.Ledger,
  @publication_host.ClientModelReadPreparation,
) raise {
  let original : Ref[
    (@resources.Ledger, @publication_host.ClientModelReadPreparation)?,
  ] = Ref(None)
  let response = terminal
  let (active, work) = async_response_fixture(
    calls,
    polls,
    Ref(0),
    cleanup_calls,
    Ref(true),
    release,
    response,
    current~,
    prepare_original=Some(active => {
      let (ledger, read) = original_preparation_test_read(
        active,
        quantities=Some(active.quantity_capacity.unwrap().limits),
      )
      bind_original_model_preparation(active, read, 100L, 5L).unwrap()
      original.val = Some((ledger, read))
    }),
    observe_response_call=Some((slot, original) => {
      let inner = if ready.val {
        match per_slot {
          Some(read) => read(slot)
          None => response
        }
      } else {
        @model.PhysicalPending
      }
      if io_closed.val {
        @model.PhysicalIoQuiescent(original, inner)
      } else {
        @model.PhysicalIoPending(original, inner)
      }
    }),
  )
  let (ledger, read) = original.val.unwrap()
  (active, work, ledger, read)
}

///|
test "original Model IO binding refuses a fresh fixture Ledger and cancels before claim" {
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 1, 1).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  let calls = Ref(0)
  let (ordinary, _) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    [],
    Ref(true),
    Ref(true),
    @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, }),
  )
  assert_true(
    @model.bind_prepared_model_io_access(
      prepared_call_set(ordinary).unwrap(),
      access,
    )
    is Err(_),
  )
  async_io_stop_and_cleanup(ordinary)
  let (original, _, ledger, read) = original_io_consumer_fixture(
    calls,
    Ref(false),
    Ref(false),
    Ref(true),
  )
  @model.bind_prepared_model_io_access(
    prepared_call_set(original).unwrap(),
    access,
  ).unwrap()
  async_io_stop_and_cleanup(original)
  assert_eq(calls.val, 0)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  original_preparation_test_release(ledger, read)
  assert_true(@resources.close_model_io_access(access).unwrap())
}

///|
test "original Model IO claim before authority refusal retires only after cursor cleanup" {
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 1, 1).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  let current = Ref(evidence_account(@authorization.Allow))
  let calls = Ref(0)
  let (original, work, ledger, read) = original_io_consumer_fixture(
    calls,
    Ref(false),
    Ref(false),
    Ref(true),
    current~,
  )
  @model.bind_prepared_model_io_access(
    prepared_call_set(original).unwrap(),
    access,
  ).unwrap()
  current.val = evidence_account(@authorization.Deny)
  assert_true(
    fixture_finish(original, initial_work=work)
    is Failed(Model(@model.Authorization(_)), ..),
  )
  assert_eq(calls.val, 0)
  assert_eq(
    @model.stopped_model_attempt_count(original.model.unwrap()),
    Some(0),
  )
  // The claim precedes original attempt/Entry creation. Refusal is not itself
  // a cursor retirement ACK; the same cleanup owner still owes that work.
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((1, 1)),
  )
  async_io_stop_and_cleanup(original)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  assert_eq(calls.val, 0)
  original_preparation_test_release(ledger, read)
  assert_true(@resources.close_model_io_access(access).unwrap())
}

///|
test "original Model IO response before close retains active and holding duties" {
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 1, 1).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  let calls = Ref(0)
  let io_closed = Ref(false)
  let release = Ref(true)
  let cleaned : Array[Bool] = []
  let (original, work, ledger, read) = original_io_consumer_fixture(
    calls,
    Ref(true),
    io_closed,
    release,
    cleanup_calls=cleaned,
  )
  @model.bind_prepared_model_io_access(
    prepared_call_set(original).unwrap(),
    access,
  ).unwrap()
  guard fixture_finish(original, initial_work=work) is Settling(_, work=settled) else {
    abort("original response must reach its original settlement")
  }
  assert_eq(calls.val, 1)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((1, 1)),
  )
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(original).unwrap()),
  )
  async_assert_wait(original, settled)
  assert_eq(cleaned.length(), 0)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((1, 1)),
  )
  // A ready response and Store ACK cannot substitute for the same port's
  // quiescence. A later checked close releases only its own original duty.
  io_closed.val = true
  async_io_stop_and_cleanup(original)
  assert_eq(calls.val, 1)
  assert_eq(cleaned.length(), 1)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  original_preparation_test_release(ledger, read)
  assert_true(@resources.close_model_io_access(access).unwrap())
}

///|
test "original Model Unknown IO close cannot issue holding settlement or repeat cleanup" {
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 1, 1).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  let calls = Ref(0)
  let cleanup_calls : Array[Bool] = []
  let (original, work, ledger, _) = original_io_consumer_fixture(
    calls,
    Ref(true),
    Ref(true),
    Ref(true),
    terminal=@model.PhysicalUnknown({ input_tokens: None, output_tokens: None, }),
    cleanup_calls~,
  )
  @model.bind_prepared_model_io_access(
    prepared_call_set(original).unwrap(),
    access,
  ).unwrap()
  assert_true(fixture_finish(original, initial_work=work) is Failed(_, ..))
  assert_eq(calls.val, 1)
  let before = @resources.ledger_usage(ledger)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 1)),
  )
  // Physical cleanup alone is not the original Store/Journal settlement ACK.
  // Preserve this intentionally unresolved in-memory double, not a live IO/DB.
  assert_false(cleanup(original).unwrap())
  assert_eq(cleanup_calls.length(), 1)
  assert_false(cleanup(original).unwrap())
  assert_eq(cleanup_calls.length(), 1)
  assert_eq(calls.val, 1)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 1)),
  )
  assert_false(@resources.close_model_io_access(access).unwrap())
}

///|
test "original Model shared IO admission keeps two Run holding separate from IO close" {
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 1, 1).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  let first_calls = Ref(0)
  let first_ready = Ref(false)
  let first_io = Ref(false)
  let first_release = Ref(false)
  let (first, first_work, first_ledger, first_read) = original_io_consumer_fixture(
    first_calls, first_ready, first_io, first_release,
  )
  let second_calls = Ref(0)
  let second_ready = Ref(false)
  let second_io = Ref(false)
  let second_release = Ref(false)
  let (second, second_work, second_ledger, second_read) = original_io_consumer_fixture(
    second_calls, second_ready, second_io, second_release,
  )
  assert_false(physical_equal(first_ledger, second_ledger))
  let first_set = prepared_call_set(first).unwrap()
  @model.bind_prepared_model_io_access(first_set, access).unwrap()
  assert_true(@model.bind_prepared_model_io_access(first_set, access) is Err(_))
  @model.bind_prepared_model_io_access(
    prepared_call_set(second).unwrap(),
    access,
  ).unwrap()
  guard fixture_finish(first, initial_work=first_work) is AwaitIo(work=waiting) else {
    abort("first original IO is pending")
  }
  assert_eq(first_calls.val, 1)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((1, 1)),
  )
  guard fixture_finish(second, initial_work=second_work)
    is AwaitIo(work=blocked) else {
    abort("second Run must await shared capacity before Entry")
  }
  assert_eq(second_calls.val, 0)
  async_assert_wait(second, blocked)
  first_io.val = true
  async_assert_wait(first, waiting)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 1)),
  )
  // Quiescent inner Pending does not return Store/Journal/SDK holding.
  async_assert_wait(second, blocked)
  assert_eq(second_calls.val, 0)
  first_ready.val = true
  guard fixture_finish(first, initial_work=waiting) is Settling(0, work=settled) else {
    abort("original response awaits Store settlement")
  }
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 1)),
  )
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(first).unwrap()),
  )
  async_assert_wait(first, settled)
  async_assert_wait(second, blocked)
  assert_eq(second_calls.val, 0)
  // Even acknowledged persistence cannot return failed physical/SDK cleanup.
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 1)),
  )
  first_release.val = true
  async_io_stop_and_cleanup(first)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  assert_eq(first_calls.val, 1)
  original_preparation_test_release(first_ledger, first_read)
  assert_true(fixture_finish(second, initial_work=blocked) is AwaitIo(..))
  assert_eq(second_calls.val, 1)
  second_io.val = true
  second_ready.val = true
  assert_true(
    fixture_finish(second, initial_work=second.work) is Settling(0, ..),
  )
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(second).unwrap()),
  )
  second_release.val = true
  async_io_stop_and_cleanup(second)
  original_preparation_test_release(second_ledger, second_read)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  assert_true(@resources.close_model_io_access(access).unwrap())
}
