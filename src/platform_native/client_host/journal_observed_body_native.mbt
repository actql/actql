///|
// Only the selected submitted row uses an observed physical extent. Legacy
// DB methods keep their original limit. Body copies and the codec are separate
// constructors in the SAME original Read, never a new resource/permission.
fn journal_submitted_retained(
  bytes : Int,
  text_units : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    // Row/intent/reference/admission/state projection and optional carriers.
    record_headers: 32L,
    reference_slots: 64L,
    scalar_words: 32L,
    // Body copy during parsing; only the actual accepted output text survives
    // canonical comparison. Parser/source/builder alternatives belong to E.
    owned_utf16_units: text_units + 71L,
    owned_wire_bytes: bytes.to_int64(),
  }
}

///|
fn journal_submitted_decode_working(
  stage : @host.ClientSubmittedJournalConstruction,
) -> (Int64, Int64, Int64)? {
  let (bytes, text_units, nodes, depth, parsing) = match stage {
    @host.SubmittedJournalParse(bytes) => (bytes, 0L, 65536, 64, true)
    @host.SubmittedJournalCanonical(bytes, text_units, nodes, depth) =>
      (bytes, text_units, nodes, depth, false)
  }
  if bytes <= 0 ||
    bytes >= 2147483519 ||
    nodes < 1 ||
    nodes > 65536 ||
    depth < 0 ||
    depth > 64 ||
    text_units < 0L ||
    text_units > 3L * bytes.to_int64() {
    return None
  }
  guard @execution.preparation_representation_cost(
      journal_submitted_retained(bytes, text_units),
    )
    is Some(retained) &&
    @decode.preserving_json_admission_construction_inventory(bytes, 16, 2)
    is Some(outer_parser) &&
    @source.json_tree_retained_construction_extent(
      16,
      15,
      1,
      0,
      bytes.to_int64(),
    )
    is Some(outer_tree) &&
    @decode.preserving_json_parser_construction_inventory(
      bytes,
      nodes,
      Int::max(1, depth),
    )
    is Some(inner_parser) else {
    return None
  }
  let outer : @execution.PreparationRepresentationUnits = {
    record_headers: outer_tree.record_headers,
    reference_slots: outer_tree.reference_slots,
    scalar_words: outer_tree.scalar_words,
    owned_utf16_units: outer_tree.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  let parser : @execution.PreparationRepresentationUnits = {
    record_headers: inner_parser.record_headers,
    reference_slots: inner_parser.reference_slots,
    scalar_words: inner_parser.scalar_words,
    owned_utf16_units: inner_parser.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  let first : @execution.PreparationRepresentationUnits = {
    record_headers: outer_parser.record_headers,
    reference_slots: outer_parser.reference_slots,
    scalar_words: outer_parser.scalar_words,
    owned_utf16_units: outer_parser.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  let scratch = if parsing {
    // Outer parser scratch has returned before the intent parser starts.
    // Its tree/index and original intent text remain beside that parser.
    guard @execution.compose_preparation_representation([outer, parser])
      is Some(inner) &&
      @execution.preparation_representation_cost(first) is Some(first_cost) &&
      @execution.preparation_representation_cost(inner) is Some(inner_cost) else {
      return None
    }
    Int64::max(first_cost, inner_cost)
  } else {
    let n = nodes.to_int64()
    let d = depth.to_int64() + 1L
    // from_source(data_keys=true): one value variant and field tuple per node;
    // output/FrozenArray collections, active duplicate-key Maps and recursive
    // map/sort controls. Strings borrow the SAME parsed Source text. Whole-tree
    // array/map endpoints deliberately overbound the actual disjoint shapes.
    guard @shape.collection_construction_extent({
        records: 2L * n + 8L * d + 1L,
        record_references: 4L * n + 16L * d,
        record_words: 3L * n + 12L * d,
        reference_arrays: 2L * n + 1L,
        reference_items: 3L * n,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: Int64::min(n, d),
        map_entries: n,
      })
      is Some(canonical) &&
      @source.json_tree_retained_construction_extent(
        nodes,
        nodes - 1,
        nodes,
        0,
        bytes.to_int64(),
      )
      is Some(tree) &&
      @encode.text_writer_construction_inventory(bytes, nodes, depth)
      is Some(text) &&
      @encode.hash_writer_construction_inventory(nodes + 4, depth + 1)
      is Some(hash) &&
      @encode.text_writer_construction_inventory(bytes, 16, 2)
      is Some(comparison) else {
      return None
    }
    // Text emission, hash and full-row canonical comparison are sequential,
    // but conservatively co-count their bounded controls and buffers here.
    // The original body and both returned text domains remain in retained.
    let rest : @execution.PreparationRepresentationUnits = {
      record_headers: canonical.record_headers +
      tree.record_headers +
      text.record_headers +
      hash.record_headers +
      comparison.record_headers +
      2L,
      reference_slots: canonical.reference_slots +
      tree.reference_slots +
      text.reference_slots +
      hash.reference_slots +
      comparison.reference_slots +
      3L,
      scalar_words: canonical.scalar_words +
      tree.scalar_words +
      text.scalar_words +
      hash.scalar_words +
      comparison.scalar_words +
      2L,
      owned_utf16_units: tree.owned_utf16_units +
      text.owned_utf16_units +
      hash.owned_utf16_units +
      comparison.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes + bytes.to_int64(),
    }
    guard @execution.compose_preparation_representation([outer, rest])
      is Some(total) &&
      @execution.preparation_representation_cost(total) is Some(cost) else {
      return None
    }
    cost
  }
  // Pinned Native constructors: UTF16 builder doubles from one; any tree
  // collection's contiguous backing is bounded independently by node count.
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || terminator != unit || pointer <= 0L {
    return None
  }
  let mut capacity = 1L
  while capacity < bytes.to_int64() {
    capacity *= 2L
  }
  let raw = Int64::max(
    header + (capacity + 1L) * unit,
    array_header + (12L + 3L * nodes.to_int64()) * pointer,
  )
  guard @execution.checked_preparation_add_product(retained, scratch, 1L)
    is Some(execution) else {
    return None
  }
  Some((retained, execution, raw))
}

///|
fn NativeLocalJournalReadQueries::prepare_submitted_copy(
  self : NativeLocalJournalReadQueries,
  bytes : Int64,
) -> Result[Unit, @host.ClientJournalDecodingIssue] {
  if bytes <= 0L || bytes >= 2147483519L {
    return Err(CustodyLost)
  }
  let (header, _, _, _, _) = @bootstrap.native_managed_value_layout()
  self.prepare_submitted_working(
    (header + bytes, 2L * (header + bytes), header + bytes + 1L),
  )
}

///|
fn NativeLocalJournalReadQueries::prepare_submitted_decode(
  self : NativeLocalJournalReadQueries,
  stage : @host.ClientSubmittedJournalConstruction,
) -> Result[Unit, @host.ClientJournalDecodingIssue] {
  guard journal_submitted_decode_working(stage) is Some(working) else {
    return Err(CustodyLost)
  }
  self.prepare_submitted_working(working)
}

///|
fn NativeLocalJournalReadQueries::prepare_submitted_working(
  self : NativeLocalJournalReadQueries,
  working : (Int64, Int64, Int64),
) -> Result[Unit, @host.ClientJournalDecodingIssue] {
  if self.failure is Some(_) ||
    self.original.interrupted ||
    !(self.original.active_phase is Some(@arena.HostRead)) {
    return Err(CustodyLost)
  }
  match
    self.original.host.prepare_domain_original_read_construction(
      self.original.read,
      working.0,
      working.1,
      working.2,
    ) {
    Ok(_) => Ok(())
    Err(issue) => {
      self.failure = Some(OriginalResources(@arena.Read(issue)))
      Err(CustodyLost)
    }
  }
}
