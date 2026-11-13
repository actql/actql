///|
// Metadata is retained beside later journal constructors in this same Read.
// The underlying constructor API grows max(initial + peak), not current + peak.
// Keep that live overlap explicit; success never returns attempt usage or issues
// another Read. Refused constructors never contribute a fabricated output.
fn NativeLocalJournalReadQueries::prepare_metadata_construction(
  self : NativeLocalJournalReadQueries,
  retained : Int64,
  execution : Int64,
  raw : Int64,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if self.failure is Some(_) ||
    self.original.interrupted ||
    !(self.original.active_phase is Some(@arena.HostRead)) ||
    retained < 0L ||
    execution < 0L ||
    raw < 0L {
    return Err(CapacityExceeded)
  }
  guard @execution.checked_preparation_add_product(
      self.original.metadata_retained,
      retained,
      1L,
    )
    is Some(total_retained) &&
    @execution.checked_preparation_add_product(
      self.original.metadata_retained,
      execution,
      1L,
    )
    is Some(total_execution) else {
    return Err(CapacityExceeded)
  }
  match
    self.original.host.prepare_domain_original_read_construction(
      self.original.read,
      total_retained,
      total_execution,
      raw,
    ) {
    Err(issue) => {
      self.failure = Some(OriginalResources(@arena.Read(issue)))
      Err(CapacityExceeded)
    }
    Ok(_) => {
      self.original.metadata_retained = total_retained
      Ok(())
    }
  }
}

///|
// Same writer inventory as journal emission, but the escaping wrapper returns
// a UTF16 String rather than encoded Bytes. Keep that output live in the
// metadata accumulator before later wrappers and the final row are built.
fn native_metadata_string_writer_working(
  bytes : Int,
  units : Int64,
  nodes : Int,
  depth : Int,
) -> (Int64, Int64, Int64)? {
  if bytes <= 0 || units < 0L || units > bytes.to_int64() {
    return None
  }
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: units,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(execution) else {
    return None
  }
  let (header, unit, terminator, _, _) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || terminator != unit {
    return None
  }
  let mut capacity = 1L
  while capacity < bytes.to_int64() {
    let next = capacity * 2L
    capacity = if next > 2147483647L { bytes.to_int64() } else { next }
  }
  Some(
    (
      retained,
      execution,
      Int64::max(
        header + (capacity + 1L) * unit,
        header + units * unit + terminator,
      ),
    ),
  )
}

///|
fn native_metadata_writer_limit(
  bytes : Int64,
  units : Int64,
  before_construction : ((Int64, Int64, Int64) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])?,
) -> Result[Int, NativeClientRunJournalIssue] {
  match before_construction {
    None => Ok(131072)
    Some(reserve) => {
      if bytes <= 0L || bytes >= 2147483519L {
        return Err(CapacityExceeded)
      }
      guard native_metadata_string_writer_working(bytes.to_int(), units, 8, 1)
        is Some((retained, execution, raw)) else {
        return Err(CapacityExceeded)
      }
      reserve(retained, execution, raw).map(_ => bytes.to_int())
    }
  }
}

///|
// Reuse the existing source Owner's preflight and the SAME parser cursor.
// The fixed prelude is funded first; measured tree/index construction is
// funded before take/advance. No parse is performed merely to obtain a quote.
fn native_metadata_fields_in_original_read(
  wire : String,
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[@decode.Cursor, NativeClientRunJournalIssue] {
  let controls = @source.json_source_preflight_control_extent()
  guard @execution.preparation_representation_cost({
      record_headers: controls.record_headers,
      reference_slots: controls.reference_slots,
      scalar_words: controls.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(control_cost) else {
    return Err(CapacityExceeded)
  }
  let (header, _, _, _, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || pointer <= 0L {
    return Err(CapacityExceeded)
  }
  // Every preflight record is bounded by the sum of its owned fields. These
  // are actual record field slots and <=64-bit scalars, not logical R/E bytes.
  let control_raw = header +
    controls.reference_slots * pointer +
    controls.scalar_words * 8L
  match reserve(0L, control_cost, control_raw) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let bytes = match @scalar.admit_utf8_length(wire, 2147483518) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: bytes,
    max_nodes: 8,
    max_depth: 1,
  }
  let preflight = match
    @source.start_json_source_preflight(
      wire,
      { max_input_bytes: bytes, max_nodes: 8, max_depth: 1, },
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  defer @source.cancel_json_source_preflight(preflight)
  let geometry = while true {
    match @source.advance_json_source_preflight(preflight, 4096) {
      Ok(@source.JsonSourceContinue(..)) => continue
      Ok(@source.JsonSourceReady(value, ..)) => break value
      _ => return Err(CustodyLost)
    }
  } nobreak {
    return Err(CustodyLost)
  }
  guard saved_effect_wire_construction(geometry) is Some((retained, peak, raw)) &&
    @execution.checked_preparation_add_product(control_cost, peak, 1L)
    is Some(execution) else {
    return Err(CapacityExceeded)
  }
  match reserve(retained, execution, Int64::max(raw, control_raw)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  saved_effect_admit_preflight(preflight, limits).map_err(_ => CustodyLost)
}
