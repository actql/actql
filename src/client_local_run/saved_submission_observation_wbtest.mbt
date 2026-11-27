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
    cancellation_head: record.cancellation_head,
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

///|
test "claimed live continuation reads its actual Run locator and cancellation without a census" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(preparation)
  let rows = submitted_rows_prepare(
    plan,
    preparation,
    submitted_rows_before(preparation),
  ).unwrap()
  let physical = local_observation_rows(rows, plan, preparation)
  let admitted = physical[2].1
  let (run, policy, observation) = @host.decode_client_run_journal_row_with_observation_originals(
    admitted.body,
  ).unwrap()
  let claimed = @host.client_run_journal_row_body(
    { ..run, physical_start_claimed: true, dispatch_reserved: true, },
    local_run_policy_originals=policy,
    run_observation_originals=observation,
  ).unwrap()
  physical[2] = ("client_runs", { ..admitted, body: claimed, })
  let (locator, body) = @host.client_saved_run_reference_locator(
    rows.reference,
    plan.request,
    plan.definition,
  ).unwrap()
  let located : @host.ClientJournalPhysicalRow = {
    key: locator,
    body,
    revision: 0L,
  }
  physical.push(("client_run_reference_index", located))
  let queries : Array[String] = []
  let retained : Ref[@host.ClientRunJournalRowOriginal?] = Ref(None)
  let original_reads = Ref(0)
  let stale_original = Ref(false)
  let check = (candidate, fail_witness) => {
    queries.clear()
    retained.val = None
    original_reads.val = 0
    read_local_current_saved_submission(
      rows,
      plan,
      candidate,
      (table, key) => {
        queries.push(table)
        if table == "client_cancel_originals" && fail_witness {
          Err("cancel-read")
        } else {
          local_observation_read(physical, table, key)
        }
      },
      row => {
        match
          @host.retain_client_run_journal_row_original(
            if stale_original.val { admitted.body } else { row.body },
            plan.request,
            plan.definition,
          ) {
          Ok(original) => retained.val = Some(original)
          Err(_) => return Err("custody")
        }
        local_observation_validate(row)
      },
      "custody",
      require_claimed=true,
      row_original=Some(() => {
        original_reads.val += 1
        retained.val
      }),
    )
  }
  let result = check(preparation, false).unwrap()
  assert_eq(
    local_saved_submission_revisions(result, rows, plan, preparation).unwrap(),
    (0L, 9L, 2L),
  )
  let saved = local_saved_submission_snapshot(result, rows, plan, preparation).unwrap()
  assert_true(@host.client_saved_submission_run_row(saved) is Some(_))
  assert_true(
    local_saved_submission_snapshot(result, rows, { ..plan, }, preparation)
    is Err(ForeignPreparation),
  )
  let selected = [
    "client_submitted_intents", "client_runs", "client_run_reference_index",
  ]
  assert_eq(queries, selected)
  assert_eq(original_reads.val, 1)
  stale_original.val = true
  assert_true(check(preparation, false) is Err(Rows(CustodyLost)))
  assert_eq(queries, ["client_submitted_intents", "client_runs"])
  assert_eq(original_reads.val, 1)
  stale_original.val = false
  let census : () -> Result[(Int, Int64), String] = () => Ok((0, 0L))
  guard @host.prepare_client_cancellation_journal_append(
    plan.request,
    @publication.run_definition_namespace(plan.definition).unwrap(),
    "original-claimed-cancellation",
    8,
    1024,
    run.publication_binding,
    census,
    () => Ok(Some(run)),
    value => {
      request: value.request,
      definition: value.definition,
      revision: 8L,
      cancellation_requested: false,
      publication_binding: value.publication_binding,
    },
    _ => Ok(None),
    _ => Ok(false),
    () => true,
  ) is Ok(@host.AppendCancellation(cancel)) else { fail("missing original accepted cancellation") }
  let (cancel_key, receipt, witness, _, _) = @host.client_cancellation_append_rows(cancel).unwrap()
  let cancelled = @host.client_run_journal_row_body(
    {
      ..run,
      physical_start_claimed: true,
      dispatch_reserved: true,
      cancellation_head: @host.client_cancellation_append_accepted_head(cancel),
    },
    local_run_policy_originals=policy,
    run_observation_originals=observation,
  ).unwrap()
  physical[2] = ("client_runs", { ..admitted, body: cancelled, })
  let exact_receipt : @host.ClientJournalPhysicalRow = { key: cancel_key, body: receipt, revision: 0L, }
  let exact_witness : @host.ClientJournalPhysicalRow = { key: cancel_key, body: witness, revision: 0L, }
  physical.push(("client_cancellations", exact_receipt))
  physical.push(("client_cancel_originals", exact_witness))
  // A different operation is the explicit whole-Store audit's concern.
  physical.push(("client_cancellations", { ..exact_receipt, key: "unrelated", body: b"unrelated", }))
  assert_true(check(preparation, false) is Ok(_))
  assert_eq(queries, [..selected, "client_cancellations", "client_cancel_originals"])
  assert_true(check(preparation, true) is Err(Inspection("cancel-read")))
  assert_eq(queries, [..selected, "client_cancellations", "client_cancel_originals"])
  physical[6] = ("client_cancel_originals", { ..exact_witness, revision: 1L, })
  assert_true(check(preparation, false) is Err(Inspection("custody")))
  physical[5] = ("client_cancellations", { ..exact_receipt, key: "foreign", })
  assert_true(check(preparation, false) is Err(Inspection("custody")))
  assert_eq(queries, [..selected, "client_cancellations"])
  let copied = submitted_rows_preparation("SELECT 1 AS n")
  assert_true(check(copied, false) is Err(Rows(ForeignPreparation)))
  assert_eq(queries, [])
  physical[4] = ("client_run_reference_index", { ..located, revision: 1L, })
  assert_true(check(preparation, false) is Err(Inspection("custody")))
  assert_eq(queries, selected)
  physical[4] = ("client_run_reference_index", { ..located, body: b"foreign", })
  assert_true(check(preparation, false) is Err(Inspection("custody")))
  assert_eq(queries, selected)
  physical[2] = ("client_runs", admitted)
  assert_true(check(preparation, false) is Err(Rows(CustodyLost)))
  assert_eq(queries, ["client_submitted_intents", "client_runs"])
}

///|
test "first admitted Run reobserves exact original generations without visiting other rows" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(preparation)
  let rows = submitted_rows_prepare(
    plan, preparation, submitted_rows_before(preparation),
  ).unwrap()
  let physical = local_observation_rows(rows, plan, preparation)
  let (_, run) = physical[2]
  let (_, submitted) = physical[3]
  let run = { ..run, revision: 0L, }
  let submitted = { ..submitted, revision: 1L, }
  physical[2] = ("client_runs", run)
  physical[3] = ("client_submitted_intents", submitted)
  let (key, body) = @host.client_saved_run_reference_locator(
    rows.reference, plan.request, plan.definition,
  ).unwrap()
  let locator : @host.ClientJournalPhysicalRow = { key, body, revision: 0L, }
  physical.push(("client_run_reference_index", locator))
  physical.push(("client_runs", { ..run, key: "unrelated", body: b"unrelated", }))
  let queries : Array[String] = []
  let observe = (candidate, fail_locator) => {
    queries.clear()
    read_local_first_saved_submission(
      rows, plan, candidate,
      (table, key) => {
        queries.push(table)
        if table == "client_run_reference_index" && fail_locator {
          Err("physical")
        } else {
          local_observation_read(physical, table, key)
        }
      },
      local_observation_validate,
      "original",
    )
  }
  let observed = observe(preparation, false).unwrap()
  assert_eq(
    local_saved_submission_revisions(observed, rows, plan, preparation).unwrap(),
    (0L, 0L, 1L),
  )
  assert_eq(queries, [
    "client_submitted_intents", "client_runs", "client_run_reference_index",
  ])
  assert_true(observe(preparation, true) is Err(Inspection("physical")))
  physical[4] = ("client_run_reference_index", { ..locator, revision: 1L, })
  assert_true(observe(preparation, false) is Err(Inspection("original")))
  physical[4] = ("client_run_reference_index", locator)
  physical[2] = ("client_runs", { ..run, revision: 1L, })
  assert_true(observe(preparation, false) is Err(Inspection("original")))
  assert_eq(queries, ["client_submitted_intents", "client_runs"])
  physical[2] = ("client_runs", { ..run, body: b"foreign", })
  assert_true(observe(preparation, false) is Err(Inspection("original")))
  physical[2] = ("client_runs", run)
  physical[3] = ("client_submitted_intents", { ..submitted, revision: 2L, })
  assert_true(observe(preparation, false) is Err(Inspection("original")))
  assert_eq(queries, ["client_submitted_intents"])
}
