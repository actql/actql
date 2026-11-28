///|
// Kinds 7 and 8 hold only a candidate for the one existing Run and its
// exact predecessors. Python still owns the physical CAS and its Unknown.
priv struct StoredMockEffectSDKStart {
  rows : Int
  dispatch : Int?
  capacity : @resources.CapacityReservation
  mut step : @host.ClientEffectFirstStartStep?
  mut confirmed : Bool
  mut reading : Bool
}

///|
fn mock_effect_start_run(value : Instance, run : StoredRun) -> Bool {
  value.preparations.get(run.preparation)
  is Some(
    {
      kind: RETAINED_MOCK_REQUEST_KIND,
      project_request: Some({ effect_plan: Some({ journal: Some(_), .. }), .. }),
      ..
    }
  )
}

///|
fn mock_effect_start_dependencies(
  value : Instance,
  run : Int,
  kind : Int,
  producing : Int?,
) -> Result[(Int, Int?), Int] {
  let mut rows : Int? = None
  let mut dispatch : Int? = None
  for (key, child) in value.materials {
    if child.run != run || child.closing || producing == Some(key) {
      continue
    }
    if child.kind == kind {
      return Err(-35)
    }
    if child.kind == 6 &&
      child.produced &&
      child.submission is Some({ first_journal_observed: true, .. }) {
      guard rows is None else { return Err(-35) }
      rows = Some(key)
    }
    if kind == 8 &&
      child.kind == 7 &&
      child.mock_start is Some({ confirmed: true, step: Some(_), .. }) {
      guard dispatch is None else { return Err(-35) }
      dispatch = Some(key)
    }
  }
  guard rows is Some(rows) && (kind == 7 || dispatch is Some(_)) else {
    return Err(-35)
  }
  Ok((rows, dispatch))
}

///|
const MOCK_EFFECT_START_CONTROLS : Int64 = 4096L

///|
fn mock_effect_step_retained(step : @host.ClientEffectFirstStartStep) -> Int64 {
  let (row, body) = @host.client_effect_first_start_step_row(step)
  MOCK_EFFECT_START_CONTROLS +
  row.body.length().to_int64() +
  body.length().to_int64() +
  2L * row.key.length().to_int64()
}

///|
fn mock_effect_start_same_row(
  actual : @host.ClientJournalPhysicalRow,
  expected : @host.ClientJournalPhysicalRow,
) -> Bool {
  actual.key == expected.key &&
  actual.revision == expected.revision &&
  actual.body == expected.body
}

///|
fn mock_effect_start_next_row(
  step : @host.ClientEffectFirstStartStep,
) -> @host.ClientJournalPhysicalRow {
  let (before, body) = @host.client_effect_first_start_step_row(step)
  { key: before.key, revision: before.revision + 1L, body, }
}

///|
fn[T] with_mock_effect_start_read(
  value : Instance,
  handle : Int,
  start : StoredMockEffectSDKStart,
  successor : Bool,
  consume : (
    MockEffectJournalObservationOriginal,
    @host.ClientSavedSubmissionSnapshot,
    @host.ClientJournalPhysicalRow,
    @host.ClientEffectFirstStartStep?,
    (Int64, Int64) -> Result[Unit, Int],
  ) -> Result[T, Int],
  managed? : @local_host.ClientInstalledManagedRun? = None,
) -> Result[T, Int] {
  if start.reading {
    return Err(-33)
  }
  guard value.materials.get(handle) is Some(material) &&
    !material.closing &&
    value.runs.get(material.run) is Some(run) &&
    value.run_configurations.get(run.configuration) is Some(configuration) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(physical) else {
    return Err(-2)
  }
  let original = match
    mock_effect_journal_observation_original(
      value,
      start.rows,
      run.configuration,
      managed~,
    ) {
    Err(code) => return Err(code)
    Ok(original) => original
  }
  guard physical_equal(configuration, original.configuration) else {
    return Err(-32)
  }
  let dispatch = match start.dispatch {
    None => None
    Some(key) => {
      guard value.materials.get(key) is Some(parent) &&
        parent.kind == 7 &&
        parent.run == material.run &&
        !parent.closing &&
        parent.mock_start
        is Some({ rows, confirmed: true, step: Some(step), .. }) &&
        rows == start.rows else {
        return Err(-35)
      }
      Some(step)
    }
  }
  let step = start.step
  let expected = match step {
    Some(step) => {
      let (before, _) = @host.client_effect_first_start_step_row(step)
      if successor {
        mock_effect_start_next_row(step)
      } else {
        before
      }
    }
    None =>
      match dispatch {
        Some(step) => mock_effect_start_next_row(step)
        None => {
          let (run, _, _, _) = @host.client_effect_run_journal_append_rows(
            original.candidate,
          )
          let (key, body, _, _) = @host.client_run_journal_append_rows(run)
          { key, revision: 0L, body, }
        }
      }
  }
  fn current() -> Result[Unit, Int] {
    let code = mock_effect_journal_observation_current(
      value,
      start.rows,
      run.configuration,
      physical.physical,
      original,
      managed~,
    )
    if code != 0 {
      return Err(code)
    }
    guard start.reading &&
      !material.closing &&
      value.materials.get(handle) is Some(actual) &&
      physical_equal(actual, material) &&
      actual.mock_start is Some(selected) &&
      physical_equal(selected, start) &&
      value.host_currents.get(current_handle) is Some(scope) &&
      physical_equal(physical, scope) else {
      return Err(-9)
    }
    Ok(())
  }
  let retained = step
    .map(mock_effect_step_retained)
    .unwrap_or(MOCK_EFFECT_START_CONTROLS)
  start.reading = true
  let outcome = current().bind(_ => {
    with_mock_effect_journal_snapshot(
      value,
      original,
      expected,
      physical.physical,
      start.capacity,
      retained,
      current,
      (saved, locator, fund) => {
        consume(original, saved, locator, dispatch, fund)
      },
    )
  })
  start.reading = false
  outcome
}

///|
fn sdk_journal_writer_capacity(bytes : Int, nodes : Int, depth : Int) -> Int64? {
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: writer.record_headers,
    reference_slots: writer.reference_slots,
    scalar_words: writer.scalar_words,
    owned_utf16_units: writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn prepare_mock_effect_start_wire(
  material : StoredMaterial,
  original : MockEffectJournalObservationOriginal,
  saved : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  dispatch : @host.ClientEffectFirstStartStep?,
  fund : (Int64, Int64) -> Result[Unit, Int],
) -> Result[(@host.ClientEffectFirstStartStep, Bytes), Int] {
  guard @host.client_saved_submission_run_row(saved) is Some(before) &&
    sdk_journal_writer_capacity(4096, 32, 2) is Some(request_scratch) else {
    return Err(-4)
  }
  let row_bytes = before.body.length().to_int64() +
    2L * before.key.length().to_int64()
  match fund(row_bytes, request_scratch + 4096L) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let decode_peak = Ref(request_scratch + 4096L)
  let refused = Ref(false)
  let step = match
    @host.prepare_client_effect_first_start_step(
      original.preparing,
      saved,
      original.journal.materials,
      original.candidate,
      locator,
      true,
      dispatch~,
      before_decode=Some(stage => {
        guard @host.client_run_journal_decode_construction(stage)
          is Some((body, scratch)) &&
          fund(row_bytes, body + scratch + request_scratch + 4096L) is Ok(_) else {
          refused.val = true
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        decode_peak.val = Int64::max(
          decode_peak.val,
          body + scratch + request_scratch + 4096L,
        )
        Ok(())
      }),
      before_encode=Some((bytes, nodes, depth) => {
        guard sdk_journal_writer_capacity(bytes, nodes, depth) is Some(scratch) &&
          fund(row_bytes + bytes.to_int64(), decode_peak.val + scratch) is Ok(_) else {
          refused.val = true
          return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
        }
        Ok(())
      }),
    ) {
    Ok(step) => step
    Err(_) if refused.val => return Err(-4)
    Err(Observation(_)) => return Err(-32)
    Err(InvalidOriginal | ForeignRun | ChangedIntent) => return Err(-35)
    Err(CapacityExceeded) => return Err(-4)
    Err(Encoding(_)) => return Err(-34)
  }
  let (_, body) = @host.client_effect_first_start_step_row(step)
  let limit = Int::min(1048576, 6 * (body.length() + before.key.length()) + 160)
  guard sdk_journal_writer_capacity(limit, 6, 1) is Some(scratch) &&
    fund(
      row_bytes + body.length().to_int64(),
      scratch + 2L * body.length().to_int64() + limit.to_int64(),
    )
    is Ok(_) else {
    return Err(-4)
  }
  let source_count = if step.dispatch {
    None
  } else {
    Some(original.effect.sources.length())
  }
  sdk_start_step_wire(material.kind, before, body, limit, source_count~).map(wire => {
    (step, @utf8.encode(wire))
  })
}

///|
fn produce_mock_effect_sdk_start(
  value : Instance,
  handle : Int,
  material : StoredMaterial,
  run : StoredRun,
) -> Int {
  if value.closing ||
    value.runtime_closing ||
    material.closing ||
    material.output_closed {
    return -5
  }
  if material.produced && material.mock_start is Some(start) {
    return observe_mock_effect_sdk_start(value, handle, start, false)
  }
  if material.invoked {
    return -33
  }
  let (rows, dispatch) = match
    mock_effect_start_dependencies(
      value,
      material.run,
      material.kind,
      Some(handle),
    ) {
    Err(code) => return code
    Ok(deps) => deps
  }
  guard run.sdk_submission is Some(_) else { return -2 }
  let capacity = match
    @resources.reserve_capacity(
      value.root,
      MOCK_EFFECT_START_CONTROLS,
      MOCK_EFFECT_START_CONTROLS,
    ) {
    Err(_) => return -4
    Ok(capacity) => capacity
  }
  let start : StoredMockEffectSDKStart = {
    rows,
    dispatch,
    capacity,
    step: None,
    confirmed: false,
    reading: false,
  }
  material.mock_start = Some(start)
  material.invoked = true
  let (step, wire) = match
    with_mock_effect_start_read(value, handle, start, false, (
      original,
      saved,
      locator,
      dispatch,
      fund,
    ) => {
      prepare_mock_effect_start_wire(
        material, original, saved, locator, dispatch, fund,
      )
    }) {
    Err(code) => return code
    Ok(projected) => projected
  }
  start.step = Some(step)
  guard @resources.shrink_capacity_reservation(
      value.root,
      capacity,
      mock_effect_step_retained(step),
      0L,
    )
    is Ok(_) else {
    return -4
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, material.slot, wire),
  )
  if code == 0 {
    material.produced = true
  }
  code
}

///|
fn observe_mock_effect_sdk_start(
  value : Instance,
  handle : Int,
  start : StoredMockEffectSDKStart,
  successor : Bool,
  managed? : @local_host.ClientInstalledManagedRun? = None,
  read_confirmed_claim? : Bool = false,
) -> Int {
  guard value.materials.get(handle) is Some(material) &&
    material.produced &&
    (
      !material.output_closed ||
      (
        read_confirmed_claim &&
        successor &&
        material.kind == 8 &&
        start.confirmed
      )
    ) &&
    start.step is Some(step) else {
    return -2
  }
  let outcome = with_mock_effect_start_read(
    value,
    handle,
    start,
    successor,
    (original, saved, locator, _, _) => {
      guard mock_effect_saved_snapshot_matches(original, saved, locator) &&
        @host.client_saved_submission_run_row(saved) is Some(actual) else {
        return Err(-35)
      }
      let (before, _) = @host.client_effect_first_start_step_row(step)
      let matches = if successor {
        @host.confirm_client_effect_first_start_step(step, actual)
      } else {
        mock_effect_start_same_row(actual, before)
      }
      if matches {
        Ok(())
      } else {
        Err(-35)
      }
    },
    managed~,
  )
  let settled = @resources.shrink_capacity_reservation(
    value.root,
    start.capacity,
    mock_effect_step_retained(step),
    0L,
  )
  match outcome {
    Err(code) => code
    Ok(_) if settled is Err(_) => -4
    Ok(_) => {
      if successor {
        start.confirmed = true
      }
      0
    }
  }
}

///|
fn mock_effect_physical_claim(
  value : Instance,
  custody : StoredPhysicalStart,
) -> (Int, StoredMockEffectSDKStart)? {
  guard custody.sdk_step is Some(handle) &&
    value.materials.get(handle) is Some(material) &&
    material.run == custody.run &&
    material.kind == 8 &&
    material.mock_start is Some(claim) else {
    return None
  }
  Some((handle, claim))
}

///|
fn check_mock_effect_physical_start(
  value : Instance,
  custody : StoredPhysicalStart,
  handle : Int,
  claim : StoredMockEffectSDKStart,
) -> Int {
  guard custody.invoked &&
    claim.confirmed &&
    !claim.reading &&
    claim.step is Some(step) &&
    custody.mock_managed is Some(managed) &&
    value.materials.get(handle) is Some(material) &&
    !material.closing &&
    material.run == custody.run &&
    claim.dispatch is Some(dispatch) &&
    value.materials.get(dispatch) is Some(parent) &&
    !parent.closing &&
    parent.run == material.run &&
    parent.kind == 7 &&
    parent.mock_start is Some({ rows, confirmed: true, step: Some(_), .. }) &&
    rows == claim.rows else {
    return -33
  }
  let original = match
    mock_effect_journal_observation_original(
      value,
      claim.rows,
      custody.current_configuration,
      managed=Some(managed),
    ) {
    Ok(original) => original
    Err(issue) => return issue
  }
  guard original.configuration.host_current is Some(current) &&
    value.host_currents.get(current) is Some(physical) else {
    return -32
  }
  claim.reading = true
  let observed = reobserve_original_mock_effect_claim(
    value, custody, handle, material, claim, step, original, managed, physical,
  )
  claim.reading = false
  let returned = @resources.shrink_capacity_reservation(
    value.root,
    claim.capacity,
    mock_effect_step_retained(step),
    0L,
  )
  match observed {
    Err(issue) => issue
    Ok(_) => if returned is Ok(_) { 0 } else { -4 }
  }
}

///|
// The original confirmed Claim knows its three canonical predecessor and
// successor bodies. Point observations use their exact keys/lengths in this
// physical Read. Cancellation advances the same Run row. The exact original
// successor and the live adoption/current fence are both required.
fn reobserve_original_mock_effect_claim(
  value : Instance,
  custody : StoredPhysicalStart,
  handle : Int,
  material : StoredMaterial,
  claim : StoredMockEffectSDKStart,
  step : @host.ClientEffectFirstStartStep,
  original : MockEffectJournalObservationOriginal,
  managed : @local_host.ClientInstalledManagedRun,
  physical : StoredHostCurrent,
) -> Result[Unit, Int] {
  fn current() -> Result[Unit, Int] {
    let code = mock_effect_journal_observation_current(
      value,
      claim.rows,
      custody.current_configuration,
      physical.physical,
      original,
      managed=Some(managed),
    )
    if code != 0 {
      return Err(code)
    }
    guard claim.reading &&
      !material.closing &&
      value.materials.get(handle) is Some(actual) &&
      physical_equal(actual, material) &&
      actual.mock_start is Some(selected) &&
      physical_equal(selected, claim) else {
      return Err(-9)
    }
    Ok(())
  }
  let (_, before, accepted, (locator_key, locator_body)) = @host.client_effect_run_journal_append_rows(
    original.candidate,
  )
  let run = mock_effect_start_next_row(step)
  let retained = mock_effect_step_retained(step)
  let scratch = 16384L +
    2L *
    (
      accepted.length().to_int64() +
      run.body.length().to_int64() +
      locator_body.length().to_int64()
    )
  match current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if physical_journal_schema(physical.physical) != 1 {
    return Err(-41)
  }
  guard @resources.grow_capacity_reservation(
      value.root,
      claim.capacity,
      retained,
      scratch,
    )
    is Ok(_) else {
    return Err(-4)
  }
  fn read_original(
    table,
    expected : @host.ClientJournalPhysicalRow,
  ) -> Result[Unit, Int] {
    match
      physical_journal_row(
        physical.physical,
        current,
        1,
        table,
        expected.key,
        expected_body_length=Some(expected.body.length()),
      ) {
      Ok(Some(row)) if mock_effect_start_same_row(row, expected) => Ok(())
      Ok(_) => Err(-35)
      Err(issue) => Err(issue)
    }
  }
  let expected_rows : Array[(String, @host.ClientJournalPhysicalRow)] = [
    (
      "client_submitted_intents",
      { key: before.key, revision: before.revision + 1L, body: accepted, },
    ),
    ("client_runs", run),
    (
      "client_run_reference_index",
      { key: locator_key, revision: 0L, body: locator_body, },
    ),
  ]
  for (table, expected) in expected_rows {
    match read_original(table, expected) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  // The admitted Claim successor is exact. Cancellation must advance that
  // same Run row and cannot leave these bytes and generation current.
  current()
}

///|
fn adopt_mock_effect_physical_start(
  value : Instance,
  custody : StoredPhysicalStart,
  handle : Int,
  claim : StoredMockEffectSDKStart,
) -> Int {
  if custody.invoked {
    return check_mock_effect_physical_start(value, custody, handle, claim)
  }
  if !claim.confirmed {
    return -35
  }
  let checked = observe_mock_effect_sdk_start(
    value,
    handle,
    claim,
    true,
    read_confirmed_claim=true,
  )
  if checked != 0 {
    return checked
  }
  let original = match
    mock_effect_journal_observation_original(
      value,
      claim.rows,
      custody.current_configuration,
    ) {
    Err(code) => return code
    Ok(original) => original
  }
  guard original.effect.sdk_run == Some(custody.run) &&
    value.runs.get(custody.run) is Some(run) &&
    value.preparations.get(run.preparation) is Some(preparation) &&
    preparation.project_request is Some(held) &&
    held.parent is Some(owner) &&
    @resources.preparation_body_borrow_value(original.journal.plan)
    is Some(borrowed) &&
    physical_equal(borrowed, original.effect.plan) else {
    return -35
  }
  // From this point the same start owns any pending cleanup. The retained
  // journal borrow returns before the managed Run takes the funded Plan.
  custody.invoked = true
  match @resources.return_preparation_body_borrow(original.journal.plan) {
    Ok(false) => ()
    Ok(true) | Err(_) => return -9
  }
  match
    @local_host.begin_request_effect_managed_run(owner, original.effect.request) {
    Ok(managed) => {
      custody.mock_managed = Some(managed)
      0
    }
    Err(InsufficientCapacity | MetadataCapacityUnavailable) => -4
    Err(CleanupPending) => -9
    Err(ForeignOriginal) => -2
    Err(_) => -23
  }
}

///|
fn retire_mock_effect_physical_start(
  value : Instance,
  custody : StoredPhysicalStart,
) -> Int {
  guard custody.mock_managed is Some(managed) else { return 0 }
  guard value.runs.get(custody.run) is Some(run) &&
    value.preparations.get(run.preparation) is Some(preparation) &&
    preparation.project_request is Some(held) else {
    return -9
  }
  if @local_host.quiesce_installed_managed_run(managed) is Err(_) {
    return -9
  }
  if !retire_original_mock_effect_evidence(custody) {
    return -4
  }
  // Remove the Request bridge's alias before the managed Owner retires the
  // Plan and its capacity. A pending stop remains reachable on this start.
  held.effect_plan = None
  match @local_host.retire_installed_managed_run(managed) {
    Err(Resource(Unavailable)) => {
      let code = report_mock_project_child_stop(held)
      if code != 0 {
        return code
      }
      let code = retire_mock_project_access(held, preparation.slot)
      if code != 0 {
        return code
      }
      if @local_host.retire_installed_managed_run(managed) is Err(_) {
        return -9
      }
    }
    Err(_) => return -9
    Ok(_) => ()
  }
  held.parent = None
  held.initial = None
  held.frame = None
  custody.mock_managed = None
  0
}
