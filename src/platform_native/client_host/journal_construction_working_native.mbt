///|
// The shared writer owns its logical construction inventory. Native separately
// quotes the actual pinned builder's variable contiguous requests: capacity starts
// at one and doubles; UTF16 array/String/Bytes headers come from the real C ABI.
// No logical R/E deficit, policy ceiling or free-memory number becomes raw size.
fn journal_row_construction_working(
  output_bytes : Int,
  nodes : Int,
  depth : Int,
) -> (Int64, Int64, Int64)? {
  guard @encode.text_writer_construction_inventory(output_bytes, nodes, depth)
    is Some(inventory) &&
    @execution.preparation_representation_cost({
      // The observed row emitter retains one existing StringEmitCursor.
      record_headers: inventory.record_headers + 1L,
      reference_slots: inventory.reference_slots + 3L,
      scalar_words: inventory.scalar_words + 2L,
      owned_utf16_units: inventory.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(execution) &&
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: output_bytes.to_int64(),
    })
    is Some(retained) else {
    return None
  }
  let (header, unit, terminator, _array_header, _pointer) = @bootstrap.native_managed_value_layout()
  // The pinned runtime has UTF16 Strings. A different representation must
  // supply its actual constructor recipe rather than inherit this one.
  if header <= 0L || unit != 2L || terminator != unit {
    return None
  }
  let bound = output_bytes.to_int64()
  let mut capacity = 1L
  while capacity < bound {
    let next = capacity * 2L
    capacity = if next > 2147483647L { bound } else { next }
  }
  // moonbit_malloc_array owns one extra element for both scalar arrays and
  // Strings; fixed writer controls stay in the original Read's finite basis.
  let builder = header + (capacity + 1L) * unit
  let string = header + bound * unit + terminator
  let bytes = header + bound + 1L
  // Only the returned Bytes escapes this constructor into the journal plan.
  // Writer/buffers/finish String remain simultaneous execution scratch; their
  // inventory must not also be charged as retained output.
  Some((retained, execution, Int64::max(builder, Int64::max(string, bytes))))
}

///|
fn NativeLocalJournalReadQueries::prepare_row_construction(
  self : NativeLocalJournalReadQueries,
  output_bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[Unit, @host.ClientJournalEncodingIssue] {
  if self.failure is Some(_) ||
    self.original.interrupted ||
    !(self.original.active_phase is Some(@arena.HostRead)) {
    return Err(CapacityExceeded)
  }
  guard journal_row_construction_working(output_bytes, nodes, depth)
    is Some((retained, execution, raw)) else {
    return Err(CapacityExceeded)
  }
  match
    self.original.host.prepare_domain_original_read_construction(
      self.original.read,
      retained,
      execution,
      raw,
    ) {
    Err(issue) => {
      // Keep the actual original cause for the existing transaction/cleanup
      // caller. The codec's refusal never fabricates a new grant or ACK.
      self.failure = Some(OriginalResources(@arena.Read(issue)))
      Err(CapacityExceeded)
    }
    Ok(_) => Ok(())
  }
}
