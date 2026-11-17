///|
fn result_read_wire_controls() -> Int64? {
  let source = @source.json_source_preflight_control_extent()
  let work = @resources.preparation_phase_work_continuation64_construction_inventory()
  // Two retained Some carriers2H2R2W; the operation's result/tuple and
  // borrowed owner/input/wire roots2H6R6W. Source owns its parser/poll/geometry
  // inventory; Work owns its same original state and continuation closures.
  @execution.preparation_representation_cost({
    record_headers: 4L + source.record_headers + work.record_headers,
    reference_slots: 8L + source.reference_slots + work.reference_slots,
    scalar_words: 8L + source.scalar_words + work.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// One finite scan envelope on the SAME original READ, before physical rows.
/// Actual UTF16 preflight work plus each row's final transition fits the
/// selected payload bytes + row count. Returning never refills that work.
pub fn[I] begin_request_result_read_wire(
  owner : ClientRequestPreparation[I],
  input : I,
  payload_bytes : Int64,
  row_count : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ResultRead &&
    owner.result_read is Some(read) &&
    read.wire_work is None &&
    !result_read_metadata_active(owner) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if payload_bytes < 0L || row_count < 0 {
    return Err(Policy)
  }
  guard @execution.checked_preparation_add_product(
      payload_bytes,
      row_count.to_int64(),
      1L,
    )
    is Some(maximum) else {
    return Err(Policy)
  }
  let controls = result_read_wire_controls().unwrap()
  let old = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  owner.phase = Selecting
  let reserved = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    old.0 + controls,
    old.1 + controls,
  )
  owner.phase = ResultRead
  match reserved {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  read.base_retention += controls
  read.base_execution += controls
  let work = match
    @resources.begin_preparation_phase_work_continuation64(
      owner.capacity,
      input,
      @resources.ShapeInspection,
      maximum,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Work(issue))
  }
  read.wire_work = Some(work)
  @resources.return_preparation_phase_work_continuation64(work).map_err(issue => {
    Work(issue)
  })
}

///|
/// Before physical framer growth, retain ALL original buffers/Text/wire terms.
/// Only the not-yet-constructed JSON forests wait for actual raw geometry.
pub fn[I] grow_request_result_read_frame(
  owner : ClientRequestPreparation[I],
  input : I,
  units : Int,
) -> Result[(Int, Int), ClientRequestPreparationIssue] {
  guard owner.phase == ResultRead &&
    owner.result_read is Some(read) &&
    read.wire_work is Some(_) &&
    read.wire_preflight is None &&
    !result_read_metadata_active(owner) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if units < 0 || units > read.max_row {
    return Err(Policy)
  }
  if units <= read.row_units {
    return Ok((read.row_units, read.window))
  }
  let high = Int::min(
    read.max_row,
    Int::max(
      units,
      if read.row_units > read.max_row / 2 {
        read.max_row
      } else {
        Int::max(32, read.row_units * 2)
      },
    ),
  )
  reserve_request_result_read_row_cost(
    owner,
    input,
    read,
    high,
    result_read_row_nodes_cost(high, 0).unwrap(),
  )
}

///|
/// Retain the SAME immutable raw row, never expected schema or a caller census.
/// No grammar/tree/normalization work is performed by this Source preflight.
pub fn[I] begin_request_result_read_wire_row(
  owner : ClientRequestPreparation[I],
  input : I,
  wire : String,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ResultRead &&
    owner.result_read is Some(read) &&
    read.wire_work is Some(work) &&
    read.wire_preflight is None &&
    !result_read_metadata_active(owner) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if wire.length() > read.row_units || wire.length() > read.max_row {
    return Err(Policy)
  }
  owner.phase = Selecting
  let current = @resources.check_working_preparation_capacity_current(
    owner.capacity,
    input,
  )
  owner.phase = ResultRead
  match current {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  match @resources.resume_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  owner.phase = Selecting
  let started = @source.start_json_source_preflight(
    wire,
    // The original serializer retains its own depth policy. Preflight never
    // enters grammar; these bounds do not replace that later admission.
    {
      max_input_bytes: read.max_row,
      max_nodes: read.max_nodes,
      max_depth: read.max_nodes,
    },
    data_keys=true,
  )
  match started {
    Ok(cursor) => read.wire_preflight = Some(cursor)
    Err(_) => ()
  }
  let returned = @resources.return_preparation_phase_work_continuation64(work)
  owner.phase = ResultRead
  match returned {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  match started {
    Err(_) => Err(Policy)
    Ok(_) => Ok(())
  }
}

///|
/// One bounded poll; the Host yields between polls and rechecks currentness.
/// Ready cancels the original scan and backs actual node demand BEFORE parse.
pub fn[I] advance_request_result_read_wire_row(
  owner : ClientRequestPreparation[I],
  input : I,
  quantum : Int,
) -> Result[(Bool, Int, Int), ClientRequestPreparationIssue] {
  guard owner.phase == ResultRead &&
    owner.result_read is Some(read) &&
    read.wire_work is Some(work) &&
    read.wire_preflight is Some(cursor) &&
    !result_read_metadata_active(owner) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if quantum < 1 || quantum > 4096 {
    return Err(Policy)
  }
  owner.phase = Selecting
  let current = @resources.check_working_preparation_capacity_current(
    owner.capacity,
    input,
  )
  owner.phase = ResultRead
  match current {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  match @resources.resume_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  owner.phase = Selecting
  let result : Result[Int?, ClientRequestPreparationIssue] = (fn() -> Result[
    Int?,
    ClientRequestPreparationIssue,
  ] {
    let poll = match @source.advance_json_source_preflight(cursor, quantum) {
      Ok(value) => value
      Err(_) => return Err(Policy)
    }
    let (nodes, spent) = match poll {
      @source.JsonSourceContinue(work~) => (None, work)
      @source.JsonSourceReady(geometry, work~) =>
        (Some(geometry.node_upper), work)
      @source.JsonSourceFailed(_, work=spent) =>
        match
          @resources.spend_preparation_phase_work_continuation64(
            work,
            spent.to_int64(),
          ) {
          Err(issue) => return Err(Work(issue))
          Ok(_) => return Err(Policy)
        }
    }
    match
      @resources.spend_preparation_phase_work_continuation64(
        work,
        spent.to_int64(),
      ) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => Ok(nodes)
    }
  })()
  let returned = @resources.return_preparation_phase_work_continuation64(work)
  owner.phase = ResultRead
  let nodes = match result {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match returned {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  match nodes {
    None => Ok((false, read.row_units, read.window))
    Some(count) => {
      @source.cancel_json_source_preflight(cursor)
      read.wire_preflight = None
      if count > read.max_nodes {
        return Err(Policy)
      }
      let row = result_read_row_nodes_cost(read.row_units, count).unwrap()
      reserve_request_result_read_row_cost(
        owner,
        input,
        read,
        read.row_units,
        row,
        shrink_window=false,
      ).map(value => (true, value.0, value.1))
    }
  }
}

///|
fn[I] finish_request_result_read_wire(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.result_read is Some(read) {
    if read.wire_preflight is Some(cursor) {
      @source.cancel_json_source_preflight(cursor)
      read.wire_preflight = None
    }
    if read.wire_work is Some(work) {
      match @resources.finish_preparation_phase_work_continuation64(work) {
        Err(issue) => return Err(Work(issue))
        Ok(_) => read.wire_work = None
      }
    }
  }
  Ok(())
}
