///|
test "publication saved-row relationship decodes one original Run row" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture()
  guard publication_binding_prepare(
      plan, preparation, rows, run, submitted, store, material,
    )
    is Ok(Append(step)) else {
    fail("original publication candidate missing")
  }
  let calls = Ref(0)
  let first : Ref[@host.ClientRunJournalEncoding?] = Ref(None)
  let decode = body => {
    calls.val += 1
    @host.decode_client_run_journal_row_with_observation_originals(body).map(value => {
      first.val = Some(value.0)
      value
    })
  }
  let decoded = publication_binding_saved_rows(
    step.original,
    run,
    submitted,
    decode_run=decode,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_true(physical_equal(decoded.0, first.val.unwrap()))
  // A subsequent observation is a distinct call: no row/revision cache.
  ignore(
    publication_binding_saved_rows(
      step.original,
      run,
      submitted,
      decode_run=decode,
    ).unwrap(),
  )
  assert_eq(calls.val, 2)
}

///|
test "saved-row original projection preserves foreign refusal before decoding" {
  let (plan, preparation, rows, run, submitted, _, _, _) = publication_binding_fixture()
  let foreign = submitted_rows_preparation("SELECT 1 AS n")
  let calls = Ref(0)
  let decode = body => {
    calls.val += 1
    @host.decode_client_run_journal_row_with_observation_originals(body)
  }
  assert_true(
    local_saved_submitted_row_originals(
      rows,
      plan,
      foreign,
      run.key,
      run.revision,
      b"invalid",
      submitted.key,
      submitted.revision,
      b"invalid",
      decode_run=decode,
    )
    is Err(ForeignPreparation),
  )
  for
    (key, revision, submission_key, submission_revision) in [
      ("foreign", 0L, submitted.key, 0L),
      (run.key, -1L, submitted.key, 0L),
      (run.key, 0L, "foreign", 0L),
      (run.key, 0L, submitted.key, -1L),
    ] {
    assert_true(
      local_saved_submitted_row_originals(
        rows,
        plan,
        preparation,
        key,
        revision,
        b"invalid",
        submission_key,
        submission_revision,
        b"invalid",
        decode_run=decode,
      )
      is Err(CustodyLost),
    )
  }
  assert_eq(calls.val, 0)
}

///|
test "publication row projection checks each actual changed successor and cancellation" {
  let (plan, preparation, rows, run, submitted, store, material, _) = publication_binding_fixture()
  guard publication_binding_prepare(
      plan, preparation, rows, run, submitted, store, material,
    )
    is Ok(Append(step)) else {
    fail("original publication candidate missing")
  }
  let (_, _, body) = local_run_publication_binding_rows(step)
  let saved = { ..run, revision: 1L, body, }
  let original = confirm_local_run_publication_binding(step, saved, submitted).unwrap()
  let (encoding, finite, observation) = @host.decode_client_run_journal_row_with_observation_originals(
    body,
  ).unwrap()
  let calls = Ref(0)
  let decode = bytes => {
    calls.val += 1
    @host.decode_client_run_journal_row_with_observation_originals(bytes)
  }
  let started = {
    ..encoding,
    dispatch_reserved: true,
    physical_start_claimed: true,
  }
  let started_body = @host.client_run_journal_row_body(
    started,
    local_run_policy_originals=finite,
    run_observation_originals=observation,
  ).unwrap()
  let result = publication_binding_saved_rows(
    original,
    { ..saved, revision: 2L, body: started_body, },
    submitted,
    decode_run=decode,
  ).unwrap()
  assert_true(result.0.physical_start_claimed)
  assert_eq(calls.val, 1)
  let cancelled = @host.client_run_journal_row_body(
    { ..started, cancellation_requested: true, },
    local_run_policy_originals=finite,
    run_observation_originals=observation,
  ).unwrap()
  assert_true(
    publication_binding_saved_rows(
      original,
      { ..saved, revision: 3L, body: cancelled, },
      submitted,
      decode_run=decode,
    )
    is Err(CustodyLost),
  )
  assert_eq(calls.val, 2)
  assert_true(
    publication_binding_saved_rows(
      original,
      { ..saved, body: b"invalid", },
      submitted,
      decode_run=decode,
    )
    is Err(SavedRows(CustodyLost)),
  )
  assert_eq(calls.val, 3)
  assert_true(
    publication_binding_saved_rows(
      original,
      saved,
      { ..submitted, body: b"invalid", },
      decode_run=decode,
    )
    is Err(SavedRows(CustodyLost)),
  )
  assert_eq(calls.val, 4)
}
