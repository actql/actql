///|
// Keep interrupted codec backing on the original material record. Normal
// return and trusted serialized close settle the same reservation.
fn settle_sdk_submitted_journal_workspace(
  value : Instance,
  submission : StoredSubmittedMaterial,
) -> Int {
  guard submission.journal_workspace is Some(workspace) else { return 0 }
  match @resources.settle_capacity(value.root, workspace) {
    Err(_) => -4
    Ok(_) => {
      submission.journal_workspace = None
      0
    }
  }
}

///|
fn settle_sdk_whole_file_candidate_workspace(
  value : Instance,
  submission : StoredSubmittedMaterial,
) -> Int {
  guard submission.file_candidate_workspace is Some(workspace) else { return 0 }
  match @resources.settle_capacity(value.root, workspace) {
    Err(_) => -4
    Ok(_) => {
      submission.file_candidate_workspace = None
      0
    }
  }
}

///|
fn close_sdk_submitted_journal_candidate(
  value : Instance,
  submission : StoredSubmittedMaterial,
) -> Int {
  let capacity = match submission.journal_candidate {
    Some(Retained(_, capacity)) | Some(RetainedFile(_, capacity, _)) => {
      submission.journal_candidate = Some(Closing(capacity))
      capacity
    }
    Some(Closing(capacity)) => capacity
    None => return 0
  }
  match @resources.settle_capacity(value.root, capacity) {
    Err(_) => -4
    Ok(_) => {
      submission.journal_candidate = None
      0
    }
  }
}

///|
// Transfer the original File material and candidate with their live coverage.
// The caller supplies the still-funded prefix for the compiled material;
// the candidate measurement deliberately counts only its new allocations.
fn retain_sdk_whole_file_journal_candidate(
  value : Instance,
  submission : StoredSubmittedMaterial,
  workspace : @resources.CapacityReservation,
  material_prefix : Int64,
  candidate : @host.ClientCapturedTaskFirstRunRows,
) -> Result[Unit, Int] {
  guard !submission.effect &&
    submission.journal_candidate is None &&
    submission.file_candidate_workspace is Some(original) &&
    physical_equal(original, workspace) else {
    return Err(-9)
  }
  guard material_prefix > 0L &&
    @host.client_captured_task_first_run_rows_retained(candidate) is Some(rows) &&
    @execution.preparation_representation_cost({
      // RetainedFile and its enclosing Some; one byte count travels with
      // the already existing reservation and original candidate references.
      record_headers: 2L,
      reference_slots: 3L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(material_prefix, rows, 1L)
    is Some(held) &&
    @execution.checked_preparation_add_product(held, controls, 1L) is Some(held) &&
    @resources.shrink_capacity_reservation(value.root, workspace, held, 0L)
    is Ok(_) else {
    return Err(-4)
  }
  guard submission.file_candidate_workspace is Some(active) &&
    physical_equal(active, workspace) &&
    submission.journal_candidate is None else {
    return Err(-9)
  }
  submission.journal_candidate = Some(RetainedFile(candidate, workspace, held))
  submission.file_candidate_workspace = None
  Ok(())
}

///|
fn sdk_mock_effect_candidate_retained(
  candidate : @host.ClientEffectRunJournalAppend,
) -> Int64? {
  let (run, _, ready, (locator, located)) = @host.client_effect_run_journal_append_rows(
    candidate,
  )
  let (key, body, _, issued) = @host.client_run_journal_append_rows(run)
  // The preparing row already belongs to the still-live original Request.
  // Count the successor tuple, candidate, both keys, byte owners and ledger
  // controls before returning the rest of the existing construction backing.
  @execution.preparation_representation_cost({
    record_headers: 12L,
    reference_slots: 24L,
    scalar_words: 8L,
    owned_utf16_units: key.length().to_int64() + locator.length().to_int64(),
    owned_wire_bytes: body.length().to_int64() +
    issued.length().to_int64() +
    ready.length().to_int64() +
    located.length().to_int64(),
  })
}

///|
fn stage_sdk_mock_effect_journal(
  value : Instance,
  handle : Int,
  output : StoredMaterial,
  submission : StoredSubmittedMaterial,
  run : StoredRun,
  preparation : StoredPreparation,
) -> Int {
  if value.closing ||
    value.runtime_closing ||
    output.closing ||
    output.output_closed {
    return -5
  }
  let validating = output.produced
  if output.invoked != validating ||
    submission.journal_workspace is Some(_) ||
    (submission.journal_candidate is Some(Retained(_, _))) != validating {
    return -33
  }
  if submission.journal_candidate is Some(Retained(original, capacity)) {
    guard sdk_mock_effect_candidate_retained(original) is Some(bytes) &&
      @resources.capacity_reservation_covers(value.root, capacity, bytes, 0L) else {
      return -4
    }
  }
  guard output.kind == 6 &&
    submission.effect &&
    submission.borrow is Ok(borrow) &&
    physical_equal(borrow.slot, run.slot) &&
    run.configuration == submission.current_configuration &&
    value.run_configurations.get(run.configuration) is Some(configuration) &&
    configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(physical_current) &&
    sdk_mock_effect_plan(value, preparation, configuration)
    is Some((check, effect)) &&
    effect.sdk_run == Some(output.run) &&
    effect.journal is Some(journal) &&
    preparation.project_request is Some(held) &&
    held.parent is Some(parent) &&
    held.submission is Some((original, snapshot)) &&
    run.sdk_submission == Some(original) &&
    value.submissions.get(original) is Some(observation) &&
    observation.append_plan is Ready(@host.Retained(saved)) &&
    physical_equal(saved, snapshot) else {
    return -2
  }
  fn current() -> Result[Unit, Int] {
    match run_configuration_current(value, configuration) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    match host_current_physical(value, physical_current) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    guard value.runs.get(output.run) is Some(actual_run) &&
      physical_equal(actual_run, run) &&
      value.host_currents.get(current_handle) is Some(actual_current) &&
      physical_equal(actual_current, physical_current) &&
      value.materials.get(handle) is Some(actual) &&
      physical_equal(actual, output) &&
      !output.closing &&
      !output.output_closed &&
      effect.journal is Some(actual_journal) &&
      physical_equal(actual_journal, journal) &&
      value.submissions.get(original) is Some(actual_observation) &&
      physical_equal(actual_observation, observation) &&
      actual_observation.append_plan is Ready(@host.Retained(actual_snapshot)) &&
      physical_equal(actual_snapshot, snapshot) else {
      return Err(-9)
    }
    let code = mock_project_effect_plan_current(value, check, effect)
    if code == 0 {
      Ok(())
    } else {
      Err(code)
    }
  }
  match current() {
    Err(code) => return code
    Ok(_) => ()
  }
  guard @host.client_effect_run_journal_candidate_workspace(
      journal.materials,
      snapshot,
    )
    is Some((retained, scratch)) else {
    return -4
  }
  let limit = if validating {
    @buffers.buffer_length(value.pool, output.slot)
  } else {
    @buffers.buffer_output_limit(value.pool, output.slot)
  }
  guard limit is Some(limit) else { return -5 }
  // The physical current callback can reenter. A nested or interrupted
  // invocation must keep its own original disposition.
  if output.invoked != validating ||
    submission.journal_workspace is Some(_) ||
    (submission.journal_candidate is Some(Retained(_, _))) != validating {
    return -33
  }
  let controls = 512L
  let held_bytes = retained + controls
  let base = held_bytes +
    scratch +
    (if validating { limit.to_int64() } else { 0L })
  let workspace = match
    @resources.reserve_capacity(value.root, held_bytes, base) {
    Err(_) => return -4
    Ok(token) => token
  }
  submission.journal_workspace = Some(workspace)
  output.invoked = true
  let peak = Ref(base)
  fn fund(additional : Int64) -> Result[Unit, Int] {
    guard submission.journal_workspace is Some(token) &&
      physical_equal(token, workspace) &&
      @execution.checked_preparation_add_product(base, additional, 1L)
      is Some(required) else {
      return Err(-9)
    }
    if required <= peak.val {
      return Ok(())
    }
    match
      @resources.grow_capacity_reservation(
        value.root,
        workspace,
        held_bytes,
        required,
      ) {
      Err(_) => Err(-4)
      Ok(_) => {
        peak.val = required
        Ok(())
      }
    }
  }
  fn borrowed_current() -> Result[Unit, Int] {
    match current() {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    guard submission.journal_workspace is Some(token) &&
      physical_equal(token, workspace) else {
      return Err(-9)
    }
    Ok(())
  }
  let scan = (table, cursor) => {
    physical_journal_row(
      physical_current.physical,
      borrowed_current,
      0,
      table,
      cursor,
    )
  }
  let read = (table, key) => {
    physical_journal_row(
      physical_current.physical,
      borrowed_current,
      1,
      table,
      key,
    )
  }
  let charge_row = row => {
    guard journal_decode_row_capacity(row) is Some((r, e)) else {
      return Err(-31)
    }
    fund(2L * r + e)
  }
  let inspect = row => {
    charge_row(row).bind(_ => submission_append_run_inspection(row))
  }
  let cancellation = () => {
    @host.inspect_client_cancellation_journal_inventory(
      1024,
      scan,
      read,
      row => {
        charge_row(row).bind(_ => submission_cancellation_run_inspection(row))
      },
      -31,
    ).map(_ => ())
  }
  guard sdk_accepted_file_read_selection_capacity(sdk)
    is Some((read_held, read_scratch)) else {
    return -4
  }
  let read_selection = match
    borrowed_current()
    .bind(_ => {
      if physical_journal_schema(physical_current.physical) == 1 {
        Ok(())
      } else {
        Err(-41)
      }
    })
    .bind(_ => fund(read_held + read_scratch))
    .bind(_ => issue_sdk_accepted_file_read_selection(configuration, sdk)) {
    Ok(selection) => selection
    Err(code) => return code
  }
  let staged : Ref[Bytes?] = Ref(None)
  let result = @local_host.prepare_request_effect_journal_append(
      parent,
      preparation.slot,
      journal.plan,
      journal.materials,
      snapshot,
      sdk.profile,
      journal.retention,
      sdk.adoption_cid,
      @publication.local_sdk_result_read_selection_cid(read_selection),
      journal.now,
      1024,
      scan,
      read,
      inspect,
      cancellation,
      -31,
      indexed_store=true,
      stage_wire=Some(
        (
          amount => borrowed_current().bind(_ => fund(amount)),
          text => {
            guard @scalar.admit_utf8_length(text, limit) is Ok(_) else {
              return Err(if validating { -35 } else { -4 })
            }
            staged.val = Some(@utf8.encode(text))
            Ok(())
          },
        ),
      ),
    )
    .map_err(sdk_run_append_issue)
    .bind(candidate => {
      borrowed_current().bind(_ => {
        guard staged.val is Some(body) else { return Err(-33) }
        if validating &&
          @buffers.buffer_wire(value.pool, output.slot) != Some(body) {
          return Err(-35)
        }
        Ok((candidate, body))
      })
    })
  let (candidate, body) = match result {
    Err(code) => {
      settle_sdk_submitted_journal_workspace(value, submission) |> ignore
      return code
    }
    Ok(held) => held
  }
  if validating {
    return settle_sdk_submitted_journal_workspace(value, submission)
  }
  guard sdk_mock_effect_candidate_retained(candidate) is Some(bytes) &&
    @resources.shrink_capacity_reservation(value.root, workspace, bytes, 0L)
    is Ok(_) else {
    settle_sdk_submitted_journal_workspace(value, submission) |> ignore
    return -4
  }
  // Transfer only the original candidate and its remaining funding. The
  // separate output buffer may now retire independently of the exact rows.
  submission.journal_candidate = Some(Retained(candidate, workspace))
  submission.journal_workspace = None
  let code = status(
    @buffers.supply_buffer_output(value.pool, output.slot, body),
  )
  if code == 0 {
    output.produced = true
  }
  code
}

///|
// A synchronous borrow of the same issued candidate and Request. It does
// not retain any physical row or authorize a later reader or Run transition.
priv struct MockEffectJournalObservationOriginal {
  configuration : StoredRunConfiguration
  check : StoredMockProjectCheck
  effect : StoredMockProjectEffectPlan
  journal : StoredMockEffectJournal
  preparing : @host.ClientSavedSubmissionSnapshot
  candidate : @host.ClientEffectRunJournalAppend
}

///|
fn mock_effect_journal_observation_original(
  value : Instance,
  rows : Int,
  configuration_handle : Int,
  managed? : @local_host.ClientInstalledManagedRun? = None,
) -> Result[MockEffectJournalObservationOriginal, Int] {
  if value.closing || value.runtime_closing {
    return Err(-5)
  }
  guard value.materials.get(rows) is Some(material) &&
    material.kind == 6 &&
    material.produced &&
    !material.closing &&
    material.submission
    is Some(
      {
        current_configuration,
        effect: true,
        journal_candidate: Some(Retained(candidate, capacity)),
        borrow: Ok(borrow),
        ..
      }
    ) &&
    current_configuration == configuration_handle &&
    value.runs.get(material.run) is Some(run) &&
    run.configuration == configuration_handle &&
    physical_equal(borrow.slot, run.slot) &&
    value.run_configurations.get(configuration_handle) is Some(configuration) &&
    configuration.host_current is Some(_) &&
    value.preparations.get(run.preparation) is Some(preparation) &&
    sdk_mock_effect_plan(value, preparation, configuration)
    is Some((check, effect)) &&
    effect.sdk_run == Some(material.run) &&
    effect.journal is Some(journal) &&
    preparation.project_request is Some(held) &&
    held.submission is Some((original, preparing)) &&
    run.sdk_submission == Some(original) &&
    value.submissions.get(original) is Some(submission) &&
    submission.kind == 3 &&
    submission.produced &&
    submission.configuration == configuration_handle &&
    submission.append_plan is Ready(@host.Retained(snapshot)) &&
    physical_equal(snapshot, preparing) else {
    return Err(-2)
  }
  match managed {
    Some(owner) =>
      if @local_host.check_installed_effect_managed_run(
          owner,
          journal.materials.prepared,
          effect.request,
        )
        is Err(_) {
        return Err(-32)
      }
    None =>
      if @resources.preparation_body_borrow_value(journal.plan) is None {
        return Err(-2)
      }
  }
  guard sdk_mock_effect_candidate_retained(candidate) is Some(bytes) &&
    @resources.capacity_reservation_covers(value.root, capacity, bytes, 0L) else {
    return Err(-4)
  }
  Ok({ configuration, check, effect, journal, preparing, candidate, })
}

///|
fn mock_effect_journal_observation_current(
  value : Instance,
  rows : Int,
  configuration_handle : Int,
  physical : Int,
  original : MockEffectJournalObservationOriginal,
  managed? : @local_host.ClientInstalledManagedRun? = None,
) -> Int {
  let configuration = original.configuration
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.client_request_program_cid(original.effect.request),
      configuration.context_cid,
    )
    is Ok(_) else {
    return -32
  }
  if physical_journal_current(physical) != 0 {
    return -41
  }
  match
    mock_effect_journal_observation_original(
      value,
      rows,
      configuration_handle,
      managed~,
    ) {
    Err(code) => code
    Ok(actual) =>
      if physical_equal(actual.configuration, configuration) &&
        physical_equal(actual.check, original.check) &&
        physical_equal(actual.effect, original.effect) &&
        physical_equal(actual.journal, original.journal) &&
        physical_equal(actual.preparing, original.preparing) &&
        physical_equal(actual.candidate, original.candidate) {
        mock_project_effect_plan_current(value, actual.check, actual.effect)
      } else {
        -9
      }
  }
}

///|
fn mock_effect_saved_snapshot_matches(
  original : MockEffectJournalObservationOriginal,
  saved : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
) -> Bool {
  let (_, before, ready, (key, body)) = @host.client_effect_run_journal_append_rows(
    original.candidate,
  )
  let actual = @host.client_saved_submission_row(saved)
  actual.key == before.key &&
  actual.revision == before.revision + 1L &&
  actual.body == ready &&
  locator.key == key &&
  locator.revision == 0L &&
  locator.body == body
}

///|
fn[T] with_mock_effect_journal_snapshot(
  value : Instance,
  original : MockEffectJournalObservationOriginal,
  expected : @host.ClientJournalPhysicalRow,
  physical : Int,
  capacity : @resources.CapacityReservation,
  base : Int64,
  current : () -> Result[Unit, Int],
  consume : (
    @host.ClientSavedSubmissionSnapshot,
    @host.ClientJournalPhysicalRow,
    (Int64, Int64) -> Result[Unit, Int],
  ) -> Result[T, Int],
) -> Result[T, Int] {
  let (_, _, _, (locator_key, _)) = @host.client_effect_run_journal_append_rows(
    original.candidate,
  )
  let task_original : @host.ClientTaskMaterialsOriginal[Unit]? = None
  with_sdk_run_journal_snapshot(
    value,
    @host.client_saved_submission_record(original.preparing).reference,
    original.effect.request,
    original.journal.materials.run_definition,
    expected,
    locator_key,
    task_original,
    physical,
    capacity,
    base,
    current,
    consume,
  )
}

///|
priv struct SDKTaskJournalReadFunding {
  mut task : Int64
}

///|
// A single funded physical read for the existing saved observation. A held
// Task material can omit pure codec reconstruction only after exact reads.
fn[Plan, T] with_sdk_run_journal_snapshot(
  value : Instance,
  reference : @host.ClientSubmissionReferenceRecord,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  expected : @host.ClientJournalPhysicalRow,
  locator_key : String,
  task_original : @host.ClientTaskMaterialsOriginal[Plan]?,
  physical : Int,
  capacity : @resources.CapacityReservation,
  base : Int64,
  current : () -> Result[Unit, Int],
  consume : (
    @host.ClientSavedSubmissionSnapshot,
    @host.ClientJournalPhysicalRow,
    (Int64, Int64) -> Result[Unit, Int],
  ) -> Result[T, Int],
  selected_file_projection? : Bool = false,
) -> Result[T, Int] {
  if selected_file_projection && task_original is None {
    return Err(-35)
  }
  guard expected.key == @host.client_request_scope_cid(request) else {
    return Err(-31)
  }
  guard submission_decode_prefix_capacity() is Some(submissions) &&
    @execution.checked_preparation_add_product(base, submissions, 1L)
    is Some(common) else {
    return Err(-4)
  }
  // A selected Task row can coexist with a fresh scan/point-read copy.
  // Its existing candidate backing is separate from this Read reservation.
  let prefix = if task_original is Some(_) {
    guard @execution.preparation_representation_cost({
        record_headers: 16L,
        reference_slots: 40L,
        scalar_words: 16L,
        owned_utf16_units: 4L * expected.key.length().to_int64(),
        owned_wire_bytes: 2L * expected.body.length().to_int64(),
      })
      is Some(control) &&
      @execution.checked_preparation_add_product(common, control, 1L)
      is Some(total) else {
      return Err(-4)
    }
    total
  } else {
    common
  }
  let retained_peak = Ref(prefix)
  let execution_peak = Ref(prefix)
  fn fund(retained : Int64, execution : Int64) -> Result[Unit, Int] {
    let retained = Int64::max(retained_peak.val, retained)
    let execution = Int64::max(execution_peak.val, execution)
    match
      @resources.grow_capacity_reservation(
        value.root,
        capacity,
        retained,
        execution,
      ) {
      Err(_) => Err(-4)
      Ok(_) => {
        retained_peak.val = retained
        execution_peak.val = execution
        Ok(())
      }
    }
  }
  match fund(prefix, prefix) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let task_read : SDKTaskJournalReadFunding? = if task_original is Some(_) {
    Some({ task: 0L, })
  } else {
    None
  }
  fn fund_task_read(
    sizes : SDKTaskJournalReadFunding,
    extra_retained : Int64,
    extra_scratch : Int64,
  ) -> Result[Unit, Int] {
    guard @execution.checked_preparation_add_product(prefix, extra_retained, 1L)
      is Some(retained) &&
      @execution.checked_preparation_add_product(retained, sizes.task, 1L)
      is Some(work) &&
      @execution.checked_preparation_add_product(work, extra_scratch, 1L)
      is Some(execution) else {
      return Err(-4)
    }
    current().bind(_ => fund(retained, execution)).bind(_ => current())
  }
  let read = (table, key) => {
    if table == "client_runs" && key != expected.key {
      return Err(-31)
    }
    physical_journal_row(physical, current, 1, table, key).bind(row => {
      if table == "client_submitted_intents" &&
        row is Some(row) &&
        (row.body.length() < 1 || row.body.length() > 262144) {
        Err(-31)
      } else {
        Ok(row)
      }
    })
  }
  fn inspect_saved_run(
    row : @host.ClientJournalPhysicalRow,
  ) -> Result[@host.ClientRunJournalInspection, Int] {
    // The original issued/claimed row must match before using its nominal
    // definition or material. A changed cancellation advances that same row.
    guard row.key == expected.key &&
      row.revision == expected.revision &&
      row.body == expected.body else {
      return Err(-31)
    }
    Ok({
      request,
      definition,
      checkpoint: None,
      cancellation_head: None,
      task_materials_cid: task_original.map(
        @host.client_task_materials_original_cid,
      ),
    })
  }
  let task_funding = task_read.map(sizes => {
    bytes => {
      sizes.task = Int64::max(sizes.task, bytes)
      fund_task_read(sizes, 0L, 0L)
    }
  })
  if physical_journal_schema(physical) != 1 {
    return Err(-41)
  }
  let saved = match
    @host.read_client_saved_submission_with_task_original(
      reference,
      read,
      inspect_saved_run,
      -31,
      task_original,
      fund_task_read=task_funding,
    ) {
    Ok(Some(saved)) => saved
    Ok(None) => return Err(-43)
    Err(code) => return Err(code)
  }
  let locator = match read("client_run_reference_index", locator_key) {
    Ok(Some(row)) => row
    Ok(None) => return Err(-31)
    Err(code) => return Err(code)
  }
  match current() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  consume(saved, locator, (retained, scratch) => {
    match task_read {
      None => fund(prefix + retained, prefix + retained + scratch)
      Some(sizes) => fund_task_read(sizes, retained, scratch)
    }
  }).bind(result => current().map(_ => result))
}

///|
fn sdk_first_journal_admission_workspace() -> Int64? {
  guard @encode.text_writer_construction_inventory(4096, 16, 3) is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + 32L,
      reference_slots: writer.reference_slots + 64L,
      scalar_words: writer.scalar_words + 32L,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(workspace) else {
    return None
  }
  Some(workspace)
}

///|
fn read_mock_effect_first_admission(
  value : Instance,
  child : StoredJournalObservation,
  frame : StoredJournalDecodeFrame,
  original : MockEffectJournalObservationOriginal,
) -> Result[Bytes, Int] {
  guard sdk_first_journal_admission_workspace() is Some(workspace) else {
    return Err(-4)
  }
  fn current() -> Result[Unit, Int] {
    let code = mock_effect_journal_observation_current(
      value,
      child.material,
      child.configuration,
      child.physical,
      original,
    )
    if code == 0 && journal_decode_frame_current(value, child, frame) {
      Ok(())
    } else {
      Err(if code != 0 { code } else { -9 })
    }
  }
  let (run, _, _, _) = @host.client_effect_run_journal_append_rows(
    original.candidate,
  )
  let (key, body, _, _) = @host.client_run_journal_append_rows(run)
  with_mock_effect_journal_snapshot(
    value,
    original,
    { key, revision: 0L, body, },
    child.physical,
    frame.capacity,
    frame.indexed_capacity + workspace,
    current,
    (saved, locator, _) => {
      @host.client_first_effect_saved_admission_wire(
        original.preparing,
        saved,
        original.journal.materials,
        original.candidate,
        locator,
      )
      .map(wire => @utf8.encode(wire))
      .map_err(_ => -31)
    },
  )
}

///|
// The File row Owner must supply the actual retained candidate, active Read
// and currentness callback. The same physical rows are inspected as for
// Effect; the captured Task material extends the original inventory check.
fn read_sdk_whole_file_first_admission(
  value : Instance,
  child : StoredJournalObservation,
  frame : StoredJournalDecodeFrame,
  preparing : @host.ClientSavedSubmissionSnapshot,
  materials : @host.ClientCapturedTaskRunMaterials,
  candidate : @host.ClientCapturedTaskFirstRunRows,
  current : () -> Result[Unit, Int],
) -> Result[Bytes, Int] {
  guard sdk_first_journal_admission_workspace() is Some(workspace) &&
    @execution.checked_preparation_add_product(
      frame.indexed_capacity,
      workspace,
      1L,
    )
    is Some(base) else {
    return Err(-4)
  }
  let (key, body, _, _) = @host.client_run_journal_append_rows(candidate.run)
  fn frame_current() -> Result[Unit, Int] {
    current().bind(_ => {
      if journal_decode_frame_current(value, child, frame) {
        Ok(())
      } else {
        Err(-9)
      }
    })
  }
  with_sdk_run_journal_snapshot(
    value,
    @host.client_saved_submission_record(preparing).reference,
    materials.request,
    materials.definition,
    { key, revision: 0L, body, },
    candidate.locator.0,
    Some(candidate.task_materials),
    child.physical,
    frame.capacity,
    base,
    frame_current,
    (saved, locator, _) => {
      @host.client_first_captured_task_saved_admission_wire(
        preparing, saved, materials, candidate, locator,
      )
      .map(wire => @utf8.encode(wire))
      .map_err(_ => -31)
    },
  )
}

///|
fn inspect_mock_effect_journal_observation(
  value : Instance,
  handle : Int,
  child : StoredJournalObservation,
) -> Int {
  if child.closing {
    return -5
  }
  if child.invoked {
    return -33
  }
  let original = match
    mock_effect_journal_observation_original(
      value,
      child.material,
      child.configuration,
    ) {
    Err(code) => return code
    Ok(original) => original
  }
  let current = mock_effect_journal_observation_current(
    value,
    child.material,
    child.configuration,
    child.physical,
    original,
  )
  if current != 0 {
    return current
  }
  if child.invoked {
    return -33
  }
  child.invoked = true
  guard open_journal_decode_frame(
      value,
      handle,
      child,
      @host.client_request_scope_cid(original.effect.request),
    )
    is Some(frame) else {
    return -4
  }
  let result = read_mock_effect_first_admission(value, child, frame, original)
  let code = finish_sdk_first_admission_observation(value, child, frame, result)
  if code == 0 &&
    value.materials.get(child.material) is Some({ submission: Some(rows), .. }) {
    rows.first_journal_observed = true
  }
  code
}

///|
fn finish_sdk_first_admission_observation(
  value : Instance,
  child : StoredJournalObservation,
  frame : StoredJournalDecodeFrame,
  result : Result[Bytes, Int],
) -> Int {
  let released = dispose_journal_decode_rows(value, frame, false)
  let settled = if released == 0 {
    child.outcome = Some(ReservingDecode(frame.capacity, frame.issue))
    settle_journal_observation_close_capacity(value, child)
  } else {
    released
  }
  match result {
    Err(code) => code
    Ok(wire) => {
      if settled != 0 {
        return settled
      }
      let code = status(
        @buffers.supply_buffer_output(value.pool, child.slot, wire),
      )
      if code == 0 {
        child.admission_produced = true
      }
      code
    }
  }
}

///|
priv struct WholeFileJournalOriginal {
  configuration : StoredRunConfiguration
  preparing : @host.ClientSavedSubmissionSnapshot
  candidate : @host.ClientCapturedTaskFirstRunRows
  funded : @resources.CapacityReservation
}

///|
// Resolve the one issued kind-6 material through the original Run parent's
// state. A copied or foreign material and a closed handle are never selected.
fn sdk_whole_file_rows_handle(
  value : Instance,
  run_handle : Int,
  configuration_handle : Int,
) -> Int? {
  guard value.runs.get(run_handle) is Some(run) &&
    run.configuration == configuration_handle &&
    value.preparations.get(run.preparation) is Some(preparation) &&
    preparation.project_request is Some(held) &&
    held.whole_file_sdk_run == Some(run_handle) &&
    held.whole_file_sdk_phase is RowsReserved(handle) &&
    value.materials.get(handle) is Some(material) &&
    material.run == run_handle &&
    material.kind == 6 &&
    !material.closing &&
    material.submission is Some(submission) &&
    submission.current_configuration == configuration_handle &&
    !submission.effect else {
    return None
  }
  Some(handle)
}

///|
// The commit and Saved observers share this held File candidate. Its wire
// buffer can retire while the candidate, Request and Read still belong here.
fn sdk_whole_file_journal_material_original(
  value : Instance,
  material_handle : Int,
  configuration_handle : Int,
  managed? : StoredSDKFileManaged? = None,
) -> Result[WholeFileJournalOriginal, Int] {
  if value.closing || value.runtime_closing {
    return Err(-5)
  }
  guard value.materials.get(material_handle) is Some(rows) &&
    rows.kind == 6 &&
    rows.produced &&
    !rows.closing &&
    rows.submission is Some(input) &&
    !input.effect &&
    input.current_configuration == configuration_handle &&
    input.borrow is Ok(_) &&
    input.journal_candidate is Some(RetainedFile(candidate, funded, bytes)) &&
    value.runs.get(rows.run) is Some(run) &&
    run.configuration == configuration_handle &&
    run.sdk_submission is Some(submission) &&
    run.restoration is None &&
    value.run_configurations.get(configuration_handle) is Some(configuration) &&
    value.preparations.get(run.preparation) is Some(preparation) &&
    sdk_whole_file_rows_handle(value, rows.run, configuration_handle) ==
    Some(material_handle) &&
    sdk_whole_file_preparing_submission(
      value,
      preparation,
      run.configuration,
      submission,
    )
    is Some((_, preparing)) else {
    return Err(-2)
  }
  let plan = candidate.task_materials.plan
  match managed {
    None => {
      guard sdk_whole_file_request(value, preparation, configuration)
        is Some(request) &&
        physical_equal(request, plan.request) else {
        return Err(-2)
      }
    }
    Some(managed) => {
      guard !managed.closing &&
        sdk_whole_file_project_parent(value, preparation, configuration)
        is Some(parent) &&
        physical_equal(parent, managed.parent) else {
        return Err(-35)
      }
      let owner = match
        @local_host.observe_request_capture_transfer(managed.transfer) {
        Ok(Some(owner)) => owner
        Err(CleanupPending) => return Err(-9)
        _ => return Err(-35)
      }
      guard @local_host.check_installed_managed_run(
          owner,
          plan.compiled.owner,
          plan.request,
        )
        is Ok(_) else {
        return Err(-35)
      }
    }
  }
  let before = @host.client_saved_submission_row(preparing)
  guard candidate.preparing.key == before.key &&
    candidate.preparing.revision == before.revision &&
    candidate.preparing.body == before.body else {
    return Err(-35)
  }
  guard bytes > 0L &&
    @resources.capacity_reservation_covers(value.root, funded, bytes, 0L) else {
    return Err(-4)
  }
  Ok({ configuration, preparing, candidate, funded, })
}

///|
fn sdk_whole_file_journal_material_current(
  value : Instance,
  material_handle : Int,
  configuration_handle : Int,
  original : WholeFileJournalOriginal,
  physical_current : () -> Result[Unit, Int],
  managed? : StoredSDKFileManaged? = None,
) -> Result[Unit, Int] {
  let { configuration, preparing, candidate, funded, } = original
  run_configuration_current(value, configuration).bind(_ => {
    let request = candidate.task_materials.plan.request
    guard @authorization.bind_dispatch_authorization(
        configuration.account,
        configuration.tuple,
        @authorization.Activation,
        @host.client_request_program_cid(request),
        configuration.context_cid,
      )
      is Ok(_) else {
      return Err(-32)
    }
    physical_current()
    .bind(_ => {
      sdk_whole_file_journal_material_original(
        value,
        material_handle,
        configuration_handle,
        managed~,
      )
    })
    .bind(selected => {
      if physical_equal(selected.configuration, configuration) &&
        physical_equal(selected.preparing, preparing) &&
        physical_equal(selected.candidate, candidate) &&
        physical_equal(selected.funded, funded) {
        Ok(())
      } else {
        Err(-9)
      }
    })
  })
}

///|
priv struct WholeFileJournalRead {
  scan : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int]
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int]
  inspect_run : (@host.ClientJournalPhysicalRow) -> Result[
    @host.ClientRunJournalInspection,
    Int,
  ]
  confirm_cancellation : () -> Result[Unit, Int]
  fund_indexes : (Int64) -> Result[Unit, Int]
  fund_task : (Int64) -> Result[Unit, Int]
}

///|
// Scope the Task-only census, decoding and physical row reader to one journal
// observation. Candidate retention belongs to the surrounding material.
fn with_sdk_whole_file_journal_read(
  value : Instance,
  handle : Int,
  output : StoredMaterial,
  submission : StoredSubmittedMaterial,
  configuration : StoredRunConfiguration,
  same_scope : (() -> Result[Unit, Int]) -> Result[Unit, Int],
  consume : (WholeFileJournalRead) -> Result[Unit, Int],
) -> Result[Unit, Int] {
  if submission.journal_workspace is Some(_) {
    return Err(-33)
  }
  guard configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(physical) else {
    return Err(-32)
  }
  // Four peak cells, grouped arguments and synchronous port closures share
  // the previous control envelope. The scoped port record adds six slots.
  guard @execution.preparation_representation_cost({
      record_headers: 41L,
      reference_slots: 86L,
      scalar_words: 64L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(base) else {
    return Err(-4)
  }
  let workspace = match @resources.reserve_capacity(value.root, base, base) {
    Err(_) => return Err(-4)
    Ok(token) => token
  }
  submission.journal_workspace = Some(workspace)
  fn current() -> Result[Unit, Int] {
    same_scope(() => {
      host_current_physical(value, physical).bind(_ => {
        guard value.host_currents.get(current_handle) is Some(still_physical) &&
          physical_equal(still_physical, physical) &&
          value.materials.get(handle) is Some(still_output) &&
          physical_equal(still_output, output) &&
          !output.output_closed &&
          output.submission is Some(still_submission) &&
          physical_equal(still_submission, submission) &&
          submission.journal_workspace is Some(active) &&
          physical_equal(active, workspace) else {
          return Err(-9)
        }
        Ok(())
      })
    })
  }
  let indexes = Ref(0L)
  let run_rows = Ref(0L)
  let task_chunks = Ref(0L)
  let cancellations = Ref(0L)
  fn fund(peak : Ref[Int64], bytes : Int64) -> Result[Unit, Int] {
    if bytes <= peak.val {
      return current()
    }
    match current() {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    let previous = peak.val
    peak.val = bytes
    let retained = base + indexes.val
    // Historical Task reads and cancellation decoding are serial. Either can
    // overlap a checked Run row and the existing census's retained indexes.
    let execution = retained +
      run_rows.val +
      Int64::max(task_chunks.val, cancellations.val)
    match
      @resources.grow_capacity_reservation(
        value.root,
        workspace,
        retained,
        execution,
      ) {
      Err(_) => {
        peak.val = previous
        Err(-4)
      }
      Ok(_) => current()
    }
  }
  let scan = (table, key) => {
    physical_journal_row(physical.physical, current, 0, table, key)
  }
  let read = (table, key) => {
    physical_journal_row(physical.physical, current, 1, table, key)
  }
  fn fund_run(row : @host.ClientJournalPhysicalRow) -> Result[Unit, Int] {
    guard journal_decode_row_capacity(row) is Some((retained, execution)) &&
      sdk_row_original_capacity(row.body.length()) is Some((_, sdk)) else {
      return Err(-31)
    }
    // The existing outer-row decoder and full SDK policy/evidence check both
    // run. Nothing borrows the newly issued candidate as a historical row.
    fund(run_rows, 2L * retained + execution + sdk)
  }
  let result = current()
    .bind(_ => {
      if physical_journal_schema(physical.physical) != 1 {
        return Err(-41)
      }
      consume({
        scan,
        read,
        inspect_run: row => {
          fund_run(row).bind(_ => submission_append_run_inspection(row))
        },
        confirm_cancellation: () => {
          @host.inspect_client_cancellation_journal_inventory(
            1024,
            scan,
            read,
            row => {
              fund_run(row).bind(_ => {
                submission_cancellation_run_inspection(row)
              })
            },
            -31,
            fund_row=Some(bytes => fund(cancellations, bytes)),
          ).map(_ => ())
        },
        fund_indexes: bytes => fund(indexes, bytes),
        fund_task: bytes => fund(task_chunks, bytes),
      })
    })
    .bind(_ => current())
  let settled = settle_sdk_submitted_journal_workspace(value, submission)
  match result {
    Err(code) => Err(code)
    Ok(_) => if settled == 0 { Ok(()) } else { Err(settled) }
  }
}

///|
// First issuance on the existing kind-6 material. The physical census lease
// returns before an independently backed candidate may reach its output.
fn stage_sdk_whole_file_journal_rows(
  value : Instance,
  handle : Int,
  output : StoredMaterial,
  submission : StoredSubmittedMaterial,
  run : StoredRun,
  preparation : StoredPreparation,
) -> Int {
  if output.invoked ||
    output.produced ||
    submission.effect ||
    submission.file_candidate_workspace is Some(_) ||
    submission.journal_candidate is Some(_) {
    return -33
  }
  let configuration_handle = submission.current_configuration
  guard output.kind == 6 &&
    run.configuration == configuration_handle &&
    value.run_configurations.get(configuration_handle) is Some(configuration) &&
    configuration.host_current is Some(physical_handle) &&
    value.host_currents.get(physical_handle) is Some(physical) &&
    preparation.project_request is Some(held) &&
    held.parent is Some(parent) &&
    sdk_whole_file_rows_handle(value, output.run, configuration_handle) ==
    Some(handle) &&
    sdk_whole_file_request(value, preparation, configuration) is Some(request) &&
    run.sdk_submission is Some(observed) &&
    sdk_whole_file_preparing_submission(
      value, preparation, configuration_handle, observed,
    )
    is Some((_, preparing)) &&
    submission.borrow is Ok(input) &&
    @buffers.buffer_wire(value.pool, input.slot) is Some(input_bytes) &&
    @buffers.buffer_output_limit(value.pool, output.slot) is Some(limit) else {
    return -2
  }
  fn same_scope(fence : () -> Result[Unit, Int]) -> Result[Unit, Int] {
    run_configuration_current(value, configuration)
    .bind(_ => {
      if @authorization.bind_dispatch_authorization(
          configuration.account,
          configuration.tuple,
          @authorization.Activation,
          @host.client_request_program_cid(request),
          configuration.context_cid,
        )
        is Err(_) {
        Err(-32)
      } else {
        fence()
      }
    })
    .bind(_ => {
      guard !value.closing &&
        !value.runtime_closing &&
        value.materials.get(handle) is Some(current_output) &&
        physical_equal(current_output, output) &&
        !output.closing &&
        !output.output_closed &&
        !output.produced &&
        output.submission is Some(current_submission) &&
        physical_equal(current_submission, submission) &&
        value.runs.get(output.run) is Some(current_run) &&
        physical_equal(current_run, run) &&
        value.preparations.get(run.preparation) is Some(current_preparation) &&
        physical_equal(current_preparation, preparation) &&
        value.run_configurations.get(configuration_handle)
        is Some(current_configuration) &&
        physical_equal(current_configuration, configuration) &&
        value.host_currents.get(physical_handle) is Some(current_physical) &&
        physical_equal(current_physical, physical) &&
        sdk_whole_file_rows_handle(value, output.run, configuration_handle) ==
        Some(handle) &&
        sdk_whole_file_request(value, preparation, configuration)
        is Some(current_request) &&
        physical_equal(current_request, request) &&
        sdk_whole_file_preparing_submission(
          value, preparation, configuration_handle, observed,
        )
        is Some((_, current_preparing)) &&
        physical_equal(current_preparing, preparing) else {
        return Err(-9)
      }
      Ok(())
    })
  }
  let current = () => same_scope(() => host_current_physical(value, physical))
  match current() {
    Err(code) => return code
    Ok(_) => ()
  }
  if output.invoked || submission.file_candidate_workspace is Some(_) {
    return -33
  }
  guard @execution.preparation_representation_cost({
      record_headers: 96L,
      reference_slots: 192L,
      scalar_words: 112L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(base) else {
    return -4
  }
  let workspace = match @resources.reserve_capacity(value.root, base, base) {
    Err(_) => return -4
    Ok(token) => token
  }
  submission.file_candidate_workspace = Some(workspace)
  output.invoked = true
  let held_bytes = Ref(base)
  let execution = Ref(base)
  fn fund(retained : Int64, scratch : Int64) -> Result[Unit, Int] {
    match current() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    guard submission.file_candidate_workspace is Some(active) &&
      physical_equal(active, workspace) &&
      @execution.checked_preparation_add_product(held_bytes.val, retained, 1L)
      is Some(total) &&
      @execution.checked_preparation_add_product(total, scratch, 1L)
      is Some(peak) else {
      return Err(-4)
    }
    let peak = Int64::max(execution.val, peak)
    match
      @resources.grow_capacity_reservation(value.root, workspace, total, peak) {
      Err(_) => Err(-4)
      Ok(_) => {
        held_bytes.val = total
        execution.val = peak
        current()
      }
    }
  }
  let first_policy_error : Ref[Int?] = Ref(None)
  let policy_hold = Ref(0L)
  let policy_peak = Ref(0L)
  fn fund_policy(stage : @host.ClientTaskPolicyConstructionStage) -> Bool {
    if first_policy_error.val is Some(_) {
      return false
    }
    guard @host.client_task_policy_construction_capacity(stage)
      is Some((retained, scratch)) else {
      first_policy_error.val = Some(-4)
      return false
    }
    match fund(retained, scratch) {
      Err(issue) => {
        first_policy_error.val = Some(issue)
        false
      }
      Ok(_) => {
        policy_hold.val += retained
        policy_peak.val = Int64::max(policy_peak.val, scratch)
        true
      }
    }
  }
  let policy_collection : @host.ClientRunPolicyCollectionFunding = {
    before_collection: () => fund_policy(@host.Collection),
    before_measure: (keys, depth) => fund_policy(@host.Measure(keys, depth)),
    before_emit: (bytes, nodes, depth) => {
      fund_policy(@host.Emit(bytes, nodes, depth))
    },
    before_admit: (bytes, nodes, depth) => {
      fund_policy(@host.Admit(bytes, nodes, depth))
    },
    before_validate: (entries, refs) => {
      fund_policy(@host.Validate(entries, refs))
    },
    current: () => {
      if first_policy_error.val is Some(_) {
        return false
      }
      match current() {
        Ok(_) => true
        Err(issue) => {
          first_policy_error.val = Some(issue)
          false
        }
      }
    },
  }
  let staged : Ref[Bytes?] = Ref(None)
  let candidate : Ref[@host.ClientCapturedTaskFirstRunRows?] = Ref(None)
  let material_prefix = Ref(base)
  let result = with_sdk_whole_file_journal_read(
      value,
      handle,
      output,
      submission,
      configuration,
      same_scope,
      journal => {
        let size = input_bytes.length()
        guard size > 0 &&
          @decode.preserving_json_admission_construction_inventory(
            size,
            Int::min(size, 16384),
            64,
          )
          is Some(packet) &&
          @host.client_task_policy_construction_capacity(
            @host.Admit(4096, 32, 4),
          )
          is Some((reference, decode_reference)) &&
          @execution.preparation_representation_cost({
            record_headers: packet.record_headers,
            reference_slots: packet.reference_slots,
            scalar_words: packet.scalar_words,
            owned_utf16_units: packet.owned_utf16_units,
            owned_wire_bytes: 2L * size.to_int64(),
          })
          is Some(input_work) else {
          return Err(-4)
        }
        match fund(0L, input_work + reference + decode_reference) {
          Err(code) => return Err(code)
          Ok(_) => ()
        }
        let now = match
          check_sdk_whole_file_rows_input(value, submission, preparing) {
          Err(code) => return Err(code)
          Ok(now) => now
        }
        let (materials, policy, _) = match
          issue_sdk_whole_file_materials(
            value,
            output.run,
            handle,
            run,
            preparation,
            configuration,
            preparing,
            current,
            (purpose, bytes, nodes, depth) => {
              guard @local_host.client_captured_task_material_body_capacity(
                  purpose, bytes, nodes, depth,
                )
                is Some((retained, scratch)) else {
                return Err(-4)
              }
              fund(retained, scratch)
            },
            fund,
          ) {
          Ok(value) => value
          Err(code) => return Err(code)
        }
        material_prefix.val = held_bytes.val
        let rows = @local_host.prepare_request_whole_file_first_journal_rows(
          parent,
          preparation.slot,
          preparing,
          materials,
          policy,
          now,
          1024,
          journal.scan,
          journal.read,
          journal.inspect_run,
          journal.confirm_cancellation,
          -31,
          fund,
          policy_collection,
          (retained, scratch) => {
            guard @decode.preserving_json_admission_construction_inventory(
                65536, 512, 8,
              )
              is Some(packet) &&
              @execution.preparation_representation_cost({
                record_headers: packet.record_headers + 2L,
                reference_slots: packet.reference_slots + 2L,
                scalar_words: packet.scalar_words + 2L,
                owned_utf16_units: packet.owned_utf16_units,
                owned_wire_bytes: 2L * 65536L,
              })
              is Some(reread) else {
              return Err(-4)
            }
            fund(retained, scratch + reread + policy_hold.val + policy_peak.val)
          },
          journal.fund_indexes,
          journal.fund_task,
          fund,
          indexed_store=true,
          stage_wire=Some(
            (
              bytes => fund(0L, bytes),
              wire => {
                guard @scalar.admit_utf8_length(wire, limit) is Ok(_) else {
                  return Err(-4)
                }
                staged.val = Some(@utf8.encode(wire))
                Ok(())
              },
            ),
          ),
        ).map_err(sdk_run_append_issue)
        match rows {
          Ok(value) => {
            candidate.val = Some(value)
            Ok(())
          }
          Err(code) => Err(first_policy_error.val.unwrap_or(code))
        }
      },
    )
    .bind(_ => current())
    .bind(_ => {
      guard candidate.val is Some(rows) && staged.val is Some(body) else {
        return Err(-33)
      }
      retain_sdk_whole_file_journal_candidate(
        value,
        submission,
        workspace,
        material_prefix.val,
        rows,
      )
      .bind(_ => current())
      .bind(_ => {
        guard submission.journal_candidate
          is Some(RetainedFile(retained, owner, _)) &&
          physical_equal(retained, rows) &&
          physical_equal(owner, workspace) else {
          return Err(-9)
        }
        let code = status(
          @buffers.supply_buffer_output(value.pool, output.slot, body),
        )
        if code != 0 {
          return Err(code)
        }
        output.produced = true
        Ok(())
      })
    })
  match result {
    Ok(_) => 0
    Err(code) => {
      settle_sdk_whole_file_candidate_workspace(value, submission) |> ignore
      code
    }
  }
}

///|
// Both SDK validation calls borrow the same issued rows. They never reissue
// the candidate or use its prospective rows as real historical records.
fn validate_sdk_whole_file_journal_rows(
  value : Instance,
  handle : Int,
  output : StoredMaterial,
  submission : StoredSubmittedMaterial,
) -> Int {
  let configuration_handle = submission.current_configuration
  let original = match
    sdk_whole_file_journal_material_original(
      value, handle, configuration_handle,
    ) {
    Ok(value) => value
    Err(code) => return code
  }
  let outcome = with_sdk_whole_file_journal_read(
    value,
    handle,
    output,
    submission,
    original.configuration,
    physical => {
      sdk_whole_file_journal_material_current(
        value, handle, configuration_handle, original, physical,
      )
    },
    journal => {
      @host.check_client_captured_task_first_run_rows_current(
        original.candidate,
        original.candidate.task_materials.plan,
        1024,
        journal.scan,
        journal.read,
        journal.inspect_run,
        journal.confirm_cancellation,
        -31,
        journal.fund_indexes,
        journal.fund_task,
        indexed_store=true,
      ).map_err(sdk_run_append_issue)
    },
  )
  match outcome {
    Ok(_) => 0
    Err(code) => code
  }
}

///|
fn sdk_whole_file_journal_observation_original(
  value : Instance,
  child : StoredJournalObservation,
) -> Result[WholeFileJournalOriginal, Int] {
  if child.closing {
    return Err(-5)
  }
  sdk_whole_file_journal_material_original(
    value,
    child.material,
    child.configuration,
  )
}

///|
fn sdk_whole_file_journal_observation_current(
  value : Instance,
  handle : Int,
  child : StoredJournalObservation,
  original : WholeFileJournalOriginal,
) -> Result[Unit, Int] {
  sdk_whole_file_journal_material_current(
    value,
    child.material,
    child.configuration,
    original,
    () => {
      if physical_journal_current(child.physical) != 0 {
        return Err(-41)
      }
      guard value.journal_observations.get(handle) is Some(actual) &&
        physical_equal(actual, child) else {
        return Err(-9)
      }
      if child.closing {
        Err(-5)
      } else {
        Ok(())
      }
    },
  )
}

///|
fn inspect_sdk_whole_file_journal_observation(
  value : Instance,
  handle : Int,
  child : StoredJournalObservation,
) -> Int {
  if child.invoked {
    return -33
  }
  let original = match
    sdk_whole_file_journal_observation_original(value, child) {
    Err(code) => return code
    Ok(selected) => selected
  }
  let { preparing, candidate, .. } = original
  let materials = candidate.task_materials.plan
  fn current() -> Result[Unit, Int] {
    sdk_whole_file_journal_observation_current(value, handle, child, original)
  }
  match current() {
    Err(code) => return code
    Ok(_) => ()
  }
  if child.invoked {
    return -33
  }
  child.invoked = true
  guard open_journal_decode_frame(
      value,
      handle,
      child,
      @host.client_request_scope_cid(materials.request),
    )
    is Some(frame) else {
    return -4
  }
  let result = read_sdk_whole_file_first_admission(
    value, child, frame, preparing, materials, candidate, current,
  )
  finish_sdk_first_admission_observation(value, child, frame, result)
}
