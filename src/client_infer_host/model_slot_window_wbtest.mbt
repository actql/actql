///|
// Original checked Program/Run/Entry handles. Physical I/O, Store ACK and byte
// allowances are existing deterministic fixtures, not normal public funding.
// The accepted M2 window must permit the second eligible original Slot to
// start while the first remains pending. This is not a JS transport fan-out.
test "two original async Slots enter before the first response settles" {
  let calls = Ref(0)
  let polls = Ref(0)
  let ready = Ref(false)
  let io_closed = Ref(false)
  let released = Ref(false)
  let cleanup_calls : Array[Bool] = []
  let (active, prefix, ledger, read) = original_io_consumer_fixture(
    calls,
    ready,
    io_closed,
    released,
    polls~,
    cleanup_calls~,
  )
  // Strengthen the old counter with the same original read Ledger and an
  // actual shared nominal admission. A plain fresh fixture Ledger is not a
  // substitute for the installed window's original resource connection.
  let installation = Ref(0)
  let admission = @resources.issue_model_io_admission(installation, 2, 2).unwrap()
  let access = @resources.issue_model_io_access(admission, installation).unwrap()
  @model.bind_prepared_model_io_access(
    prepared_call_set(active).unwrap(),
    access,
  ).unwrap()
  // This preparation-only accessor must be read before the physical phase;
  // the original handle is not reissued from a later in-flight state.
  assert_eq(
    @model.prepared_model_call_count(prepared_call_set(active).unwrap()),
    Some(2),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("original first Slot must await its original response")
  }
  // Preparing/entering the next Slot is real bounded work. Permit that work,
  // rather than requiring every advance after the first wait to remain idle.
  // A pure I/O wait still cannot invent work. Neither response becomes ready.
  let mut last_work = work
  for _ in 0..<64 {
    match advance(active, 1).unwrap() {
      Continue(work=actual) => {
        assert_true(actual >= last_work && actual - last_work <= 1L)
        last_work = actual
      }
      AwaitIo(work=actual) => assert_eq(actual, last_work)
      _ => abort("neither original response is available for adoption")
    }
    if calls.val == 2 {
      break
    }
  }
  if calls.val == 2 {
    for _ in 0..<8 {
      async_assert_wait(active, last_work)
    }
  }
  let starts_before_first_response = calls.val
  assert_true(polls.val > 0)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((2, 2)),
  )
  // Drain the same original fixture before reporting the unmet window. These
  // doubles perform no network or persistence and retain no physical debt.
  ready.val = true
  io_closed.val = true
  released.val = true
  async_io_stop_and_cleanup(active)
  original_preparation_test_release(ledger, read)
  assert_eq(
    @resources.model_io_admission_counts(admission, installation),
    Some((0, 0)),
  )
  assert_true(@resources.close_model_io_access(access).unwrap())
  assert_eq(calls.val, starts_before_first_response)
  assert_eq(
    starts_before_first_response,
    2,
    msg="both eligible original Slots must start before either response completes",
  )
}
