///|
// Explicit physical-reader/Store ports exercise the shared operation family.
// They are not an installed Journal, authorization or physical-stop fixture.
fn cancellation_operation_facts(
  value : ClientRunJournalEncoding,
  revision : Int64,
) -> ClientCancellationRunOperationFacts {
  {
    request: value.request,
    definition: value.definition,
    revision,
    cancellation_requested: value.cancellation_requested,
    publication_binding: value.publication_binding,
  }
}

///|
test "shared cancellation append preserves original Run and exact independent three rows" {
  let run = journal_encoding_original()
  let empty = [("client_cancel_custody", inventory_row("issued", b"0"))]
  let plan = prepare_client_cancellation_journal_append(
    run.request,
    "namespace-a",
    "cancel-é",
    19,
    1024,
    None,
    () => cancellation_journal_inspect(empty),
    () => Ok(Some(run)),
    value => cancellation_operation_facts(value, 19L),
    _ => Ok(None),
    _ => Ok(false),
    () => true,
  ).unwrap()
  guard plan is AppendCancellation(plan) else { fail("no new candidate") }
  assert_true(physical_equal(client_cancellation_append_original(plan), run))
  let record = client_cancellation_append_record(plan)
  assert_eq(record.action, AcceptCancellation)
  assert_eq(record.observed_revision, 20L)
  let (key, body, witness, issued_revision, issued_body) = client_cancellation_append_rows(
    plan,
  ).unwrap()
  assert_eq(key, cancellation_journal_key_fixture)
  assert_eq(body, @utf8.encode(cancellation_journal_fixture))
  assert_eq(witness, cancellation_journal_rows()[2].1.body)
  assert_eq(issued_revision, 0L)
  assert_eq(issued_body, b"1")
}

///|
test "shared cancellation replay and lookup retain immutable outcome without a new terminal observation" {
  let run = { ..journal_encoding_original(), cancellation_requested: true, }
  let original = cancellation_journal_original()
  let observed = Ref(0)
  let census = () => cancellation_journal_inspect(cancellation_journal_rows())
  let prepare = expected => {
    prepare_client_cancellation_journal_append(
      run.request,
      "namespace-a",
      "cancel-é",
      expected,
      1024,
      Some("different-live-binding"),
      census,
      () => Ok(Some(run)),
      value => cancellation_operation_facts(value, 20L),
      _ => Ok(Some(original)),
      _ => {
        observed.val += 1
        Err("must not reobserve")
      },
      () => true,
    )
  }
  guard prepare(19) is Ok(RetainedCancellation(saved)) else {
    fail("not original replay")
  }
  assert_true(physical_equal(saved, original))
  assert_eq(saved.action, AcceptCancellation)
  assert_eq(saved.observed_revision, 20L)
  assert_true(prepare(18) is Err(Operation(ChangedIntent)))
  assert_eq(observed.val, 0)
  guard lookup_client_cancellation_journal_original(
      run.request,
      "namespace-a",
      "cancel-é",
      19,
      census,
      () => Ok(Some(run)),
      value => cancellation_operation_facts(value, 20L),
      _ => Ok(Some(original)),
      () => true,
    )
    is Ok(OriginalCancellation(saved)) else {
    fail("not original lookup")
  }
  assert_true(physical_equal(saved, original))
  assert_true(
    lookup_client_cancellation_journal_original(
      run.request,
      "namespace-a",
      "cancel-é",
      18,
      census,
      () => Ok(Some(run)),
      value => cancellation_operation_facts(value, 20L),
      _ => Ok(Some(original)),
      () => true,
    )
    is Err(Operation(ChangedIntent)),
  )
}

///|
test "shared cancellation missing lookup is unresolved and failed census cannot reach another owner" {
  let run = journal_encoding_original()
  let empty = [("client_cancel_custody", inventory_row("issued", b"0"))]
  assert_true(
    lookup_client_cancellation_journal_original(
      run.request,
      "namespace-a",
      "cancel-é",
      19,
      () => cancellation_journal_inspect(empty),
      () => Ok(Some(run)),
      value => cancellation_operation_facts(value, 19L),
      _ => Ok(None),
      () => true,
    )
    is Ok(UnresolvedCancellationHistory),
  )
  let retained = Ref(0)
  let failed = prepare_client_cancellation_journal_append(
    run.request,
    "namespace-a",
    "cancel-é",
    19,
    1024,
    None,
    () => Err("original physical failure"),
    () => {
      retained.val += 1
      Ok(Some(run))
    },
    value => cancellation_operation_facts(value, 19L),
    _ => Ok(None),
    _ => Ok(false),
    () => true,
  )
  assert_true(failed is Err(Observation("original physical failure")))
  assert_eq(retained.val, 0)
}

///|
test "shared cancellation terminal current and capacity are distinct from physical stop" {
  let run = journal_encoding_original()
  let empty = [("client_cancel_custody", inventory_row("issued", b"0"))]
  let prepare = (current, terminal) => {
    prepare_client_cancellation_journal_append(
      run.request,
      "namespace-a",
      "cancel-é",
      19,
      1024,
      None,
      () => cancellation_journal_inspect(empty),
      () => Ok(Some(run)),
      value => cancellation_operation_facts(value, 19L),
      _ => Ok(None),
      _ => Ok(terminal),
      () => current,
    )
  }
  guard prepare(true, true) is Ok(AppendCancellation(plan)) else {
    fail("no terminal operation")
  }
  let record = client_cancellation_append_record(plan)
  assert_eq(record.action, AlreadyTerminal)
  assert_eq(record.observed_revision, 19L)
  assert_true(prepare(false, true) is Err(AuthorizationDenied))
  let requested = { ..run, cancellation_requested: true, }
  assert_true(
    prepare_client_cancellation_journal_append(
      requested.request,
      "namespace-a",
      "cancel-next",
      20,
      1,
      None,
      () => cancellation_journal_inspect(cancellation_journal_rows()),
      () => Ok(Some(requested)),
      value => cancellation_operation_facts(value, 20L),
      _ => Ok(None),
      _ => Ok(false),
      () => true,
    )
    is Err(CapacityExceeded),
  )
}
