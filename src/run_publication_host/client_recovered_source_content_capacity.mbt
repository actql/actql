///|
// Allocation-free lexical upper bound. Quoted punctuation is deliberately
// included: malformed and inactive fields receive no trusted-shape discount.
// This is memory geometry only, never a semantic node or Work allowance.
fn recovered_source_wire_nodes(wire : String) -> Int64 {
  let mut nodes = 1L
  for index in 0..<wire.length() {
    match wire.code_unit_at(index).to_int() {
      0x7b | 0x5b => nodes += 2L
      0x3a | 0x2c => nodes += 1L
      _ => ()
    }
  }
  nodes
}

///|
/// One synchronous construction packet on the SAME managed control. The
/// caller retains its outputs there before returning to the captured Read.
/// The Read independently funds full captured/member/Preview-row admission.
pub fn recovered_source_content_construction_capacity(
  reference_wire : String,
  binding_wire : String,
  limits : @values.ReferenceLimits,
  role : String,
) -> @execution.ExecutionCapacity? {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_text_units < 1 ||
    reference_wire.length() > limits.max_bytes ||
    binding_wire.length() > limits.max_bytes {
    return None
  }
  let units = reference_wire.length().to_int64() +
    binding_wire.length().to_int64()
  // The closed candidate regenerates the issuer and reference envelopes. The
  // 64 additional nodes cover their fixed field/key/value constructors even
  // for an invalid short input. DATA keys are preserved without NFC expansion.
  let nodes = recovered_source_wire_nodes(reference_wire) +
    recovered_source_wire_nodes(binding_wire) +
    64L
  guard @execution.execution_capacity_inventory(
      [
        { unit: ValueNodeSlots, count: nodes, copies: 4, },
        { unit: CursorRootSlots, count: nodes, copies: 4, },
        { unit: DecodedTextBytes, count: units, copies: 8, },
      ],
      [
        { unit: ValueNodeSlots, count: nodes, copies: 2, },
        { unit: CanonicalWireBytes, count: units, copies: 8, },
      ],
      RetainedAlongsideExecution,
    )
    is Some(forests) else {
    return None
  }
  // Only escaped outputs contribute R: native_output_retained accumulates
  // these packets until the SAME control retires. Parser/writer forests above
  // are a synchronous E peak, not permanent output of every getter call.
  let retained = match role {
    "classify" => 0L
    "view" =>
      // Original H1/R9/W2, view H1/R1, Some and Result H2/R2/W2.
      @execution.preparation_representation_cost({
        record_headers: 4L,
        reference_slots: 12L,
        scalar_words: 4L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }).unwrap()
    "holding" =>
      // The returned SHA256 CID and its option/result/String controls.
      @execution.preparation_representation_cost({
        record_headers: 3L,
        reference_slots: 3L,
        scalar_words: 3L,
        owned_utf16_units: 71L,
        owned_wire_bytes: 0L,
      }).unwrap()
    "inspect" =>
      // Description record H1/R7/W1; its copied MIME and effective-policy
      // Strings coexist with the issuer callbacks that retain this record.
      @execution.preparation_representation_cost({
        record_headers: 3L,
        reference_slots: 9L,
        scalar_words: 1L,
        owned_utf16_units: reference_wire.length().to_int64(),
        owned_wire_bytes: 0L,
      }).unwrap()
    "issuer" =>
      // Host validation/current closures, domain selector and opaque issuer
      // identity/mode/Ref/result. They borrow the retained description above.
      @execution.preparation_representation_cost({
        record_headers: 8L,
        reference_slots: 32L,
        scalar_words: 8L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }).unwrap()
    "metadata" =>
      // Facts, storage policy/binding, Source child/current/reader controls,
      // future view facade and their explicit closure captures. Before any
      // binding encoding, the Host rejects namespace/store/workspace/lifetime
      // mismatch, so all variable binding Strings are subsets of this Ref.
      // Four observed text spans cover binding spelling and copied DATA;
      // 2048 units cover closed keys/versions, bounded MIME and fixed CIDs.
      @execution.preparation_representation_cost({
        record_headers: 48L,
        reference_slots: 256L,
        scalar_words: 64L,
        owned_utf16_units: 4L * units + 2048L,
        owned_wire_bytes: 0L,
      }).unwrap()
    "candidate" | "issue" => {
      // Each output retains ONE original full Ref forest and its own text,
      // canonical wire, binding or issued-contract/reference controls. The
      // same lexical bound includes every field/key occurrence and backing;
      // no full parser/index/writer forest survives merely because it ran.
      guard @execution.execution_capacity_inventory_bytes([
          { unit: ValueNodeSlots, count: nodes, copies: 1, },
          { unit: DecodedTextBytes, count: units, copies: 1, },
        ])
        is Some(output) else {
        return None
      }
      output +
      @execution.preparation_representation_cost({
        record_headers: 8L,
        reference_slots: 32L,
        scalar_words: 8L,
        owned_utf16_units: 1024L,
        owned_wire_bytes: 0L,
      }).unwrap()
    }
    _ => return None
  }
  // All original parser/hash/writer classes remain simultaneously funded
  // alongside the escaped output. The packet ends before any Store await.
  guard @execution.checked_preparation_add_product(
      retained,
      @execution.execution_capacity_execution_bytes(forests),
      1L,
    )
    is Some(execution) &&
    @execution.checked_preparation_add_product(execution, 8192L, 1L)
    is Some(execution) else {
    return None
  }
  @execution.execution_capacity(retained, execution)
}
