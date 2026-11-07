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
) -> @execution.PreparationRepresentationUnits? {
  if self.closed || self.retiring {
    return None
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
  )
}
