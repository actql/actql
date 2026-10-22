///|
// The existing fixed metadata fixtures establish no Store durability or read
// permission. The reader still joins the actual selected row and Run validator.
fn saved_state_snapshot_body(state_wire : String?, observed : Bool) -> String {
  let (definition, _) = client_saved_manifest_fixture()
  let record = decode_client_submitted_journal_row(
    @utf8.encode(saved_submission_ready),
  ).unwrap()
  let (request, _, revision) = record.run_admission.unwrap()
  let body = client_submitted_intent_journal_row_body(
    client_submission_reference_record_wire(record.reference),
    record.intent,
    run_admission=Some(
      (
        request,
        @publication.publication_contract_identity(definition),
        revision,
      ),
    ),
    run_state_original=state_wire,
    run_state_observation=if observed {
      let observation = @publication.prepare_run_state_observation(
        client_saved_manifest_state, "saved-manifest-fixture", 4L, 65536, 8192, 64,
      ).unwrap()
      Some((4L, Some(observation.key())))
    } else {
      None
    },
  ).unwrap()
  @utf8.decode(body) catch {
    _ => abort("encoded fixture is not UTF-8")
  }
}

///|
fn saved_state_snapshot_read(
  body : String,
  validations : Array[String],
) -> Result[ClientSavedSubmissionSnapshot?, String] {
  let (definition, _) = client_saved_manifest_fixture()
  let rows = saved_snapshot_rows(body)
  read_client_saved_submission(
    saved_snapshot_reference(),
    (table, key) => inventory_read(rows, table, key),
    _ => {
      validations.push("original Run")
      Ok({ ..saved_snapshot_run(), definition, })
    },
    "custody",
  )
}

///|
test "saved snapshot retains one restored state and its same original Manifest" {
  let validations : Array[String] = []
  let body = saved_state_snapshot_body(
    Some(client_saved_manifest_envelope),
    true,
  )
  let snapshot = saved_state_snapshot_read(body, validations).unwrap().unwrap()
  let first = client_saved_submission_state_original(snapshot).unwrap()
  let second = client_saved_submission_state_original(snapshot).unwrap()
  assert_true(physical_equal(first, second))
  assert_true(physical_equal(first, snapshot.state_original.unwrap()))
  assert_true(
    physical_equal(first.original_manifest(), second.original_manifest()),
  )
  assert_eq(first.wire(), client_saved_manifest_envelope)
  assert_eq(first.state_wire(), client_saved_manifest_state)
  assert_eq(
    @publication.publication_contract_json(first.original_manifest()),
    client_saved_manifest_manifest,
  )
  assert_eq(client_saved_submission_row(snapshot).body, @utf8.encode(body))
  assert_eq(validations, ["original Run"])
}

///|
test "saved snapshot keeps historical and absent state metadata unavailable" {
  for original in [None, Some(client_saved_manifest_envelope)] {
    let validations : Array[String] = []
    let body = saved_state_snapshot_body(original, false)
    let snapshot = saved_state_snapshot_read(body, validations)
      .unwrap()
      .unwrap()
    assert_true(client_saved_submission_state_original(snapshot) is None)
    assert_eq(
      client_saved_submission_record(snapshot).run_state_original,
      original,
    )
    assert_true(
      client_saved_submission_record(snapshot).run_state_observation is None,
    )
    assert_eq(client_saved_submission_row(snapshot).body, @utf8.encode(body))
    assert_eq(validations, ["original Run"])
  }
}

///|
test "saved snapshot refuses invalid or foreign observed state before retention" {
  for
    invalid in [
      "not a saved original",
      client_saved_manifest_envelope.replace(
        old="sha256:0a872d347ec29b6eb772d3d8421fe4e0daa6f1f1526d3762349461d374335945",
        new="sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      ),
    ] {
    let validations : Array[String] = []
    let body = saved_state_snapshot_body(Some(invalid), true)
    assert_true(saved_state_snapshot_read(body, validations) is Err("custody"))
    assert_eq(validations, ["original Run"])
  }
}
