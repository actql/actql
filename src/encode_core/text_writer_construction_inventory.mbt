///|
/// Unbuffered TextOutput construction, including its returned String. These
/// logical units cover the pinned JS concat and non-JS fixed-buffer paths;
/// they are not measured heap/RSS, a tariff or capacity permission.
/// Original input text/keys, serializer traversal and UTF8 encoding are OUT.
/// Closed protocol adapters may use its fixed H/R/W fields as a conservative
/// constructor envelope for each actual stringify call. Their geometry must
/// cover the whole co-held fixed document forest, including literal controls;
/// actual output String domains remain separate. This is neither one global
/// Host fee nor an allowance for arbitrary provider callbacks.
pub(all) struct TextWriterConstructionInventory {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
} derive(Eq, Debug)

///|
/// Original emission bytes/nodes/open-container depth, not a policy ceiling.
/// Synchronous writer operations own at most one ordered-key cursor here;
/// externally retained resumable cursors require their own caller inventory.
/// A zero byte bound still covers initial builder storage and refusal controls.
pub fn text_writer_construction_inventory(
  output_bytes : Int,
  nodes : Int,
  depth : Int,
) -> TextWriterConstructionInventory? {
  if output_bytes < 0 || nodes < 1 || depth < 0 {
    return None
  }
  let frames = writer_frame_construction_extent(nodes, depth)
  // TextOutput1H1R1W, builder1H1R1W; two old/new fixed buffers and three
  // old/new/current String headers5H. These target alternatives co-count.
  // ASCII view+owned span2H1R2W, two escape Strings/number/Char Strings4H,
  // finish tuple1H1R3W, last/pop carriers2H2R2W, ordered cursor1H3R3W,
  // and one typed failure carrier1H1W. No SHA state/digest/hex is included.
  let b = output_bytes.to_int64()
  // Non-JS doubles from capacity1: old+new growth or backing+trimmed result
  // uses <=3B+1 UTF16 slots. JS old/new concatenation uses <=2B; its current
  // owned ASCII view is <=min(B,257). Scalar escape/Char/number scratch adds
  // 2+2+25 units. Output is valid Unicode, so UTF16 length cannot exceed B.
  Some({
    record_headers: frames.record_headers + 18L,
    reference_slots: frames.reference_slots + 9L,
    scalar_words: frames.scalar_words + 13L,
    owned_utf16_units: 3L * b +
    1L +
    Int::min(output_bytes, 257).to_int64() +
    29L,
  })
}

///|
/// Inventory the next bounded emission on THIS open text writer. Existing
/// bytes/nodes and retained frame depth come from its charged cells. The
/// caller supplies the next operation's finite fragment/node/depth additions,
/// not the output policy maxima. Writer admission still owns all refusals.
pub fn text_writer_next_construction_inventory(
  writer : Writer,
  fragment_bytes : Int,
  additional_nodes : Int,
  additional_depth : Int,
) -> TextWriterConstructionInventory? {
  guard !writer.closed &&
    writer.output is TextOutput(_) &&
    fragment_bytes >= 0 &&
    additional_nodes >= 0 &&
    additional_depth >= 0 else {
    return None
  }
  let bytes = writer.max_bytes -
    writer.remaining_bytes +
    Int::min(fragment_bytes, writer.remaining_bytes)
  guard writer_next_live_keys(writer, additional_nodes) is Some(nodes) else {
    return None
  }
  let depth = Int::max(
    writer.peak_depth,
    writer.frames.length() +
    Int::min(additional_depth, writer.max_depth - writer.frames.length()),
  )
  text_writer_construction_inventory(bytes, Int::max(1, nodes), depth)
}
