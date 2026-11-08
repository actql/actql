///|
/// Simultaneous storage of this Store's existing captured-content child. The
/// original candidate, Source bytes and Store/SQLite/Root owners are borrowed
/// and keep their separate backing. Reserve this inventory BEFORE preparing
/// the child or entering persist/confirm/cleanup. Disk quota is not this memory.
///
/// Closed records retain two intent bodies, terminal/readback/canonical bodies
/// and four writer construction peaks, including failed cleanup readback. The
/// preserving parser/index uses its original common inventory (8 nodes, depth2).
/// Writer/Reader payloads come from THIS compiled filesystem; their same Root's
/// positive diagnostic limit bounds both C and returned/decoded details.
/// Neither an unbounded Root nor an unsupported backend supplies a quote.
///
/// This is logical representation DATA, not permission, a reservation, an
/// allocator/RSS measurement or funding of the original SQLite operation.
pub fn Store::captured_content_custody_construction_inventory(
  self : Store,
  chunk_bytes : Int,
  candidate? : @publication.CapturedContentReference? = None,
) -> @execution.PreparationRepresentationUnits? {
  if self.closed || self.retiring {
    return None
  }
  let record = match candidate {
    None => None
    Some(original) => {
      guard captured_content_record_bound(
          @publication.captured_content_reference_wire(original),
          self.max_record_bytes,
        )
        is Some(bytes) else {
        return None
      }
      Some(bytes)
    }
  }
  guard self.root.diagnostic_ceiling() is Some(diagnostics) &&
    @filesystem.native_filesystem_read_layout() is Some(read) &&
    @filesystem.native_filesystem_write_layout() is Some(write) else {
    return None
  }
  captured_content_custody_inventory(
    self.max_record_bytes,
    self.active_writers.length(),
    chunk_bytes,
    diagnostics,
    read,
    write,
    canonical_record_bytes=record,
  )
}

///|
// The canonical closed record has at most seven Strings. Count array syntax,
// this exact tag, the validated 71-character holding CID, a seven-character
// state and three <=20-character generation numbers. A JSON-escaped UTF16
// unit needs at most six UTF8 bytes. This is an output/parse geometry bound,
// not another Store policy limit; raw database readback keeps its full bound.
fn captured_content_record_bound(wire : String, maximum : Int) -> Int? {
  if maximum <= 0 {
    return None
  }
  let fixed = 2L +
    6L +
    14L +
    "actql-native-captured-content-custody/0.1".length().to_int64() +
    71L +
    7L +
    3L * 20L
  @execution.checked_preparation_add_product(
    fixed,
    wire.length().to_int64(),
    6L,
  ).map(bytes => Int64::min(bytes, maximum.to_int64()).to_int())
}

///|
/// Retained representation of this SAME verified child after its original I/O
/// cleanup. No parser, writer or temporary readback remains. Durable bytes and
/// the Store/Root/SQLite originals keep their separate custody and backing.
/// This callback-free inventory is DATA, never a cleanup or currentness ACK.
pub fn CapturedContentCustody::retained_inventory(
  self : Self,
) -> @execution.PreparationRepresentationUnits? {
  guard self.closed &&
    self.committed &&
    self.verified &&
    !self.registered &&
    !self.store.closed &&
    !self.store.retiring &&
    self.writer is None &&
    self.failed_writer is None &&
    self.reader is None &&
    self.failed_reader is None &&
    self.generation is Some(_) &&
    @shape.map_retained_extent(
      1L,
      self.store.active_writers.capacity().to_int64(),
      self.store.active_writers.length().to_int64(),
    )
    is Some(registration) else {
    return None
  }
  @execution.compose_preparation_representation([
    {
      record_headers: registration.record_headers,
      reference_slots: registration.reference_slots,
      scalar_words: registration.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      // Original custody H1/R15/W8; retained generation plus Some H2/R1/W4;
      // three owned names H3; two retained record Bytes H2. Candidate wire,
      // holding/digest and Store are borrowed, not copied by this child.
      // A removed Map entry does NOT mean its bucket backing was freed.
      record_headers: 1L + 2L + 3L + 2L,
      reference_slots: 15L + 1L,
      scalar_words: 8L + 4L,
      owned_utf16_units: self.key.length().to_int64() +
      self.staging.length().to_int64() +
      self.name.length().to_int64(),
      owned_wire_bytes: self.intent.length().to_int64() +
      self.retired_record.length().to_int64(),
    },
  ])
}
