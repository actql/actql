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
