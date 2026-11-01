///|
// Core-only fixtures. The exact SQL and physical revision expectations are
// fixed independently; none of these callbacks attest an actual Store ACK.
fn local_observation_rows(
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
) -> Array[(String, @host.ClientJournalPhysicalRow)] {
  let (run_key, submission_key, _, run, submitted) = local_submitted_run_rows(
    rows, plan, preparation,
  ).unwrap()
  [
    ("client_run_custody", { key: "issued", body: b"1", revision: 0L, }),
    (
      "client_submitted_intent_custody",
      { key: "issued", body: b"1", revision: 0L, },
    ),
    ("client_runs", { key: run_key, body: run, revision: 9L, }),
    (
      "client_submitted_intents",
      { key: submission_key, body: submitted, revision: 2L, },
    ),
  ]
}

///|
fn local_observation_scan(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
  table : String,
  cursor : String,
) -> Result[@host.ClientJournalPhysicalRow?, String] {
  let mut result : @host.ClientJournalPhysicalRow? = None
  for (scope, row) in rows {
    if scope == table &&
      row.key > cursor &&
      (result is None || row.key < result.unwrap().key) {
      result = Some(row)
    }
  }
  Ok(result)
}

///|
fn local_observation_read(
  rows : Array[(String, @host.ClientJournalPhysicalRow)],
  table : String,
  key : String,
) -> Result[@host.ClientJournalPhysicalRow?, String] {
  for (scope, row) in rows {
    if scope == table && row.key == key {
      return Ok(Some(row))
    }
  }
  Ok(None)
}

///|
fn local_observation_validate(
  row : @host.ClientJournalPhysicalRow,
) -> Result[@host.ClientRunJournalInspection, String] {
  let record = match @host.decode_client_run_journal_row(row.body) {
    Ok(value) => value
    Err(_) => return Err("original-run")
  }
  // This input fixture is the initial Effect-free, checkpoint-free slice.
  // Real Host assembly must supply its existing nested/cancellation Owners.
  if record.checkpoint is Some(_) || record.effect_material_originals is Some(_) {
    return Err("unsupported-originals")
  }
  if record.publication_policy_originals is Some(wire) &&
    @host.read_client_run_policy_originals(wire) is Err(_) {
    return Err("original-policy")
  }
  Ok({
    request: record.request,
    definition: record.definition,
    checkpoint: None,
    task_materials_cid: record.task_materials_cid,
  })
}

///|
fn local_observation_inspect(
  rows : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  physical : Array[(String, @host.ClientJournalPhysicalRow)],
) -> Result[
  LocalSavedSubmissionObservation,
  LocalSavedSubmissionObservationIssue[String],
] {
  inspect_local_saved_submission(
    rows,
    plan,
    preparation,
    1024,
    (table, cursor) => local_observation_scan(physical, table, cursor),
    (table, key) => local_observation_read(physical, table, key),
    local_observation_validate,
    () => Ok(()),
    "custody",
  )
}

///|
test "saved Core observation binds full inventory and actual rows to original SQL input" {
  let preparation = submitted_rows_preparation("/*😀*/\r\nSELECT 1 AS n")
  let plan = submitted_rows_plan(preparation)
  let rows = submitted_rows_prepare(
    plan,
    preparation,
    submitted_rows_before(preparation),
  ).unwrap()
  let physical = local_observation_rows(rows, plan, preparation)
  let observed = local_observation_inspect(rows, plan, preparation, physical).unwrap()
  assert_eq(
    local_saved_submission_revisions(observed, rows, plan, preparation).unwrap(),
    (0L, 9L, 2L),
  )
  let admission = local_saved_submission_admission_wire(
    observed, rows, plan, preparation,
  ).unwrap()
  assert_true(admission.contains("\"namespaceId\":\"local\""))
  assert_true(
    admission.contains(
      "\"authorityScopeCid\":\"sha256:" + "b".repeat(64) + "\"",
    ),
  )
  assert_true(
    admission.has_suffix("\"durability\":\"durable\",\"revision\":0}"),
  )
  let foreign = submitted_rows_preparation("/*😀*/\r\nSELECT 1 AS n")
  assert_eq(
    local_saved_submission_admission_wire(observed, rows, plan, foreign),
    Err(@host.CustodyLost),
  )
  // A later physical lookup cannot mutate this original observation.
  physical[2] = ("client_runs", { ..physical[2].1, revision: 10L, })
  assert_eq(
    local_saved_submission_revisions(observed, rows, plan, preparation).unwrap(),
    (0L, 9L, 2L),
  )
}

///|
test "saved Core observation refuses extra inventory and missing count despite matching target rows" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(preparation)
  let rows = submitted_rows_prepare(
    plan,
    preparation,
    submitted_rows_before(preparation),
  ).unwrap()
  let physical = local_observation_rows(rows, plan, preparation)
  physical.push(
    (
      "client_effect_response_bytes",
      { key: "orphan", body: b"raw", revision: 0L, },
    ),
  )
  assert_true(
    local_observation_inspect(rows, plan, preparation, physical)
    is Err(Inspection("custody")),
  )
  let physical = local_observation_rows(rows, plan, preparation)
  physical[0] = (
    "client_run_custody",
    { key: "issued", body: b"0", revision: 0L, },
  )
  assert_true(
    local_observation_inspect(rows, plan, preparation, physical)
    is Err(Inspection("custody")),
  )
}

///|
test "saved Core observation keeps preparing and unresolved history separate from admitted input" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(preparation)
  let rows = submitted_rows_prepare(
    plan,
    preparation,
    submitted_rows_before(preparation),
  ).unwrap()
  let physical = local_observation_rows(rows, plan, preparation)
  physical[3] = (
    "client_submitted_intents",
    { ..physical[3].1, body: submitted_rows_before(preparation), },
  )
  assert_true(
    local_observation_inspect(rows, plan, preparation, physical)
    is Err(NotAdmitted),
  )
  assert_true(
    local_observation_inspect(rows, plan, preparation, [
      ("client_run_custody", { key: "issued", body: b"0", revision: 0L, }),
      (
        "client_submitted_intent_custody",
        { key: "issued", body: b"0", revision: 0L, },
      ),
    ])
    is Err(UnresolvedHistory),
  )
}

///|
test "copied input Plan and separately issued rows cannot acquire original observation custody" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(preparation)
  let rows = submitted_rows_prepare(
    plan,
    preparation,
    submitted_rows_before(preparation),
  ).unwrap()
  let physical = local_observation_rows(rows, plan, preparation)
  let copied = submitted_rows_preparation("SELECT 1 AS n")
  let calls : Array[String] = []
  assert_true(
    inspect_local_saved_submission(
      rows,
      plan,
      copied,
      1024,
      (table, cursor) => {
        calls.push(table)
        local_observation_scan(physical, table, cursor)
      },
      (table, key) => {
        calls.push(table)
        local_observation_read(physical, table, key)
      },
      local_observation_validate,
      () => Ok(()),
      "custody",
    )
    is Err(Rows(ForeignPreparation)),
  )
  assert_eq(calls, [])
  let observed = local_observation_inspect(rows, plan, preparation, physical).unwrap()
  assert_true(
    local_saved_submission_revisions(observed, rows, { ..plan, }, preparation)
    is Err(ForeignPreparation),
  )
  let another = submitted_rows_prepare(
    plan,
    preparation,
    submitted_rows_before(preparation),
  ).unwrap()
  assert_true(
    local_saved_submission_revisions(observed, another, plan, preparation)
    is Err(ForeignPreparation),
  )
}
