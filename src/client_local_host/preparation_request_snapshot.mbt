///|
// Native JSON capture and its detached value coexist. A single unit covers
// one visited value plus its key and String code units. Values have their
// own geometric high-water mark: long Text never fabricates tree nodes. The shared tariff
// bounds the resulting records/slots and worst-case escaped wire, including
// the copy. Borrowed caller data and small VM control frames are not copied
// into this estimate. This is logical demand, not a physical heap guarantee.
fn request_snapshot_data_bytes(units : Int64, values : Int64) -> Int64? {
  if units < 0L ||
    values < 0L ||
    values > units ||
    units > 9223372036854775807L / 8L {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: 2L * values,
    reference_slots: 4L * values,
    scalar_words: 2L * values,
    owned_utf16_units: 8L * units,
    owned_wire_bytes: 0L,
  })
}

///|
/// Grow only when the original serializer expands its observed data envelope.
/// The caller uses geometric high-water marks, not one Resource call per
/// member. No input traversal, serializer or independent reservation lives
/// here. Failed expansion cannot replace the original input or refund work.
pub fn[I] reserve_request_snapshot(
  owner : ClientRequestPreparation[I],
  input : I,
  units : Int64,
  values : Int64,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open && owner.intent_base is None else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard units >= owner.snapshot_units &&
    values >= owner.snapshot_values &&
    request_snapshot_data_bytes(units, values) is Some(bytes) else {
    return Err(Policy)
  }
  if units == owner.snapshot_units && values == owner.snapshot_values {
    return Ok(())
  }
  let base = match owner.snapshot_base {
    Some(value) => value
    None => {
      let value = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      owner.snapshot_base = Some(value)
      value
    }
  }
  guard @execution.checked_preparation_add_product(base.0, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(base.1, bytes, 1L) is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  let outcome = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  owner.phase = Open
  match outcome {
    Err(issue) => {
      // Only this attempted grow's closed Resource kind can supply failure
      // DATA. Pure scalar reads follow its original current boundary; no
      // callback, second grow, input traversal or admission occurs here.
      let dimension = match issue {
        Resource(RetentionLimit) => Some("retention")
        Resource(ExecutionLimit) => Some("execution")
        _ => None
      }
      if dimension is Some(dimension) {
        let old = match
          @resources.preparation_capacity_reserved_extents(
            owner.capacity,
            input,
          ) {
          Ok(value) => value
          Err(_) => return Err(Capacity(issue))
        }
        let limits = @resources.ledger_limits(owner.ledger)
        let usage = @resources.ledger_usage(owner.ledger)
        let available_r = limits.retained_bytes -
          usage.held_bytes -
          (usage.reserved_retention_bytes - old.0)
        let available_e = limits.execution_bytes -
          (usage.reserved_execution_bytes - old.1)
        // An imported supplier can refuse despite room in this Ledger.
        // Such failures retain the original opaque issue, never a guessed
        // numerical shortage. Other reservations/holdings remain excluded.
        if available_r >= 0L &&
          available_e >= 0L &&
          (if dimension == "retention" {
            r > available_r
          } else {
            r <= available_r && e > available_e
          }) {
          return Err(
            SnapshotCapacityExceeded(issue, {
              phase: "request_snapshot",
              dimension,
              required_retention: r,
              required_execution: e,
              available_retention: available_r,
              available_execution: available_e,
            }),
          )
        }
      }
      Err(Capacity(issue))
    }
    Ok(_) => {
      owner.snapshot_units = units
      owner.snapshot_values = values
      Ok(())
    }
  }
}
