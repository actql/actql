///|
// Actual checked cancellation constructors and saved-row reader, with explicit
// pure fixture ports. This supplies no physical COMMIT/current/stop authority.
fn stop_interest_fixture(
  terminal : Bool,
  requested : Bool,
) -> StoredCancellationAppend {
  // The cancellation operation's existing revision domain is Int. Retain the
  // same checked submission/request bytes with bounded admission/Run revisions,
  // rather than importing the targeted-reader fixture's >2^53 revision case.
  let rows = targeted_snapshot_rows().map(pair => {
    if pair.0 == "client_submitted_intents" {
      (
        pair.0,
        {
          ..pair.1,
          body: @utf8.encode(
            targeted_submission_ready.replace(old="9007199254740993", new="18"),
          ),
        },
      )
    } else if pair.0 == "client_runs" {
      (pair.0, { ..pair.1, revision: 19L, })
    } else {
      pair
    }
  })
  let snapshot = targeted_original(rows)
  let row = @host.client_saved_submission_run_row(snapshot).unwrap()
  let original = submission_run_row_original_with_identity(row, None).unwrap()
  let run = { ..original, cancellation_requested: requested, }
  let census : () -> Result[(Int, Int64), Int] = () => Ok((0, 0L))
  let plan = @host.prepare_client_cancellation_journal_append(
    run.request,
    "scope",
    "stop-original",
    row.revision.to_int(),
    8,
    run.publication_binding,
    census,
    () => Ok(Some((row, run))),
    actual => {
      request: actual.1.request,
      definition: actual.1.definition,
      revision: actual.0.revision,
      cancellation_requested: actual.1.cancellation_requested,
      publication_binding: actual.1.publication_binding,
    },
    _ => Ok(None),
    _ => Ok(terminal),
    () => true,
  ).unwrap()
  {
    original: snapshot,
    run: (row, run),
    plan: Some(plan),
    response: None,
    writes: [],
    publication: sdk_publication_observation_original(run),
    confirmed: true,
  }
}

///|
test "confirmed cancellation stop interest includes same retained accepted original" {
  let retained = stop_interest_fixture(false, false)
  let request = retained.run.1.request
  let definition = retained.run.1.definition
  assert_true(
    cancellation_stop_record(retained, request, definition) is Ok(Some(_)),
  )
  let original = cancellation_append_original_record(retained.plan.unwrap())
  retained.plan = Some(@host.RetainedCancellation(original))
  assert_true(
    cancellation_stop_record(retained, request, definition) is Ok(Some(_)),
  )
  retained.confirmed = false
  assert_true(
    cancellation_stop_record(retained, request, definition) is Err(-33),
  )
}

///|
test "no-plan nonaccepted terminal and foreign cancellation never select stop interest" {
  for
    retained in [
      stop_interest_fixture(true, false),
      stop_interest_fixture(false, true),
    ] {
    assert_true(
      cancellation_stop_record(
        retained,
        retained.run.1.request,
        retained.run.1.definition,
      )
      is Ok(None),
    )
  }
  let retained = stop_interest_fixture(false, false)
  retained.plan = None
  retained.confirmed = false
  assert_true(
    cancellation_stop_record(
      retained,
      retained.run.1.request,
      retained.run.1.definition,
    )
    is Ok(None),
  )
  // Reuse the independently authored request preimage from the row fixture.
  let foreign = @host.admit_client_request_identity_record(
    "sha256:" + "a".repeat(64),
    "foreign-request",
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "sha256:3a2347c340e9e3308264b173e037e968058af1fcec1f1c30830225716297e7cb",
    "sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010",
  ).unwrap()
  assert_true(
    cancellation_stop_record(retained, foreign, retained.run.1.definition)
    is Err(-35),
  )
  let foreign_definition = @publication.admit_publication_contract(
    "run_definition", submission_identity_other_definition, 65536, 4096, 64,
  ).unwrap()
  assert_true(
    cancellation_stop_record(
      retained,
      retained.run.1.request,
      foreign_definition,
    )
    is Err(-35),
  )
}
