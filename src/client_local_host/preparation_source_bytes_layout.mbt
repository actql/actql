///|
/// Shared Node-JS parse_json_bytes document owner recipe. Source AST/index
/// recipes deliberately exclude the input document. Each pinned utf8.decode
/// call owns: BytesView(1ref,offset/length), Uint8Array.subarray view(1ref,
/// offset/length), one-element returned FixedArray wrapper/backing(1ref and
/// length/capacity), and its decoded String. Module TextDecoder singletons
/// are borrowed; opaque engine decoder/allocator storage is not a logical
/// heap/RSS assertion. No new source bytes are copied by either view.
///
/// Inputs are original constructor facts, not caller resource authority.
/// Callers compose these units before construction on their existing Ledger.
/// Native/Worker activation needs its own backend recipe, not this JS one.
fn closed_values_js_bytes_document_layout(
  total_utf16 : Int64,
  calls : Int,
) -> @execution.PreparationRepresentationUnits? {
  if calls < 0 || total_utf16 < 0L || (calls == 0 && total_utf16 != 0L) {
    return None
  }
  let count = calls.to_int64()
  let units : @execution.PreparationRepresentationUnits = {
    record_headers: 5L * count,
    reference_slots: 3L * count,
    scalar_words: 6L * count,
    owned_utf16_units: total_utf16,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(units) is Some(_) else {
    return None
  }
  Some(units)
}
