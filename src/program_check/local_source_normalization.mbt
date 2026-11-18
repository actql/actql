///|
/// Complete only the view omitted by THIS original declaration. The existing
/// resolver owns candidate selection; this journal neither re-resolves a
/// Catalog nor discharges Source permission, currentness or execution checks.
fn local_source_normalization_entry(
  source : @sourceviews.ResolvedInput,
  available : Int,
) -> (LocalCommonNormalizationEntry, Int)? {
  let declaration = @sourceviews.declaration(source)
  guard declaration.view is None && @sourceviews.selection(source) is SoleView else {
    return None
  }
  let name = declaration.input_name
  let selected = @sourceviews.selected_name(source)
  guard local_sort_text_work(name, available) is Some(left) &&
    local_sort_text_work(selected, left) is Some(left) else {
    return None
  }
  // The existing scalar writer supplies the JSONPath quoted member spelling.
  // The actual resolver declaration already owns this stage/name binding.
  guard @encode.quoted_string_construction_extent(name) is Some((bytes, _)) &&
    bytes <= available.to_int64() else {
    return None
  }
  let key = try {
    let writer = @encode.writer(bytes.to_int(), 1, 1)
    @encode.string_value(writer, name)
    @encode.finish(writer)
  } catch {
    _ => return None
  }
  let path = "$.stages[" +
    declaration.stage_index.to_string() +
    "].inputs[" +
    key +
    "].view"
  guard local_sort_text_work(path, left) is Some(left) else { return None }
  Some(
    (
      { original: Source(source), path, authored: "null", canonical: selected, },
      left,
    ),
  )
}
