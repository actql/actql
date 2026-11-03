///|
// This optional proof reads successful values' checked type, not value data.
// It borrows fields without copying them. Unbounded or opaque shapes preserve
// the general policy. Original compilation depth and proof work bound frames;
// no new acceptance limit, compiler or graph traversal is introduced.
fn client_local_value_node_proof_depth() -> Int {
  @publication_host.client_standard_program_preparation_limits().checking.compilation.values.depth
}

///|
// Input-dependent recursive frames belong to this original Plan constructor,
// not the fixed VM baseline. Each live contract level retains the borrowed
// contract/work/shape/field, pending result and reference-owner getter frames:
// four option headers, ten references and fourteen scalar/control slots. Include
// the last depth-refused child, plus the root/schema and text-proof controls.
fn client_local_value_node_proof_scratch_bytes() -> Int64? {
  let levels = client_local_value_node_proof_depth().to_int64() + 2L
  // The SAME bounded expression-slot visitor can retain one collector array.
  // Each slot includes its original consumer/filter/optional ordinal carriers
  // (at most5H7R6W); allow two backing references per possible array entry.
  // Its collector/returned record/current borrowed getter use the fixed tail.
  // Successive original sequences are inspected synchronously, not coheld.
  let slots = client_local_scalar_text_proof_slots().to_int64()
  guard @execution.preparation_representation_cost({
      record_headers: 4L * levels + 5L * slots + 6L,
      reference_slots: 10L * levels + 10L * slots + 12L,
      scalar_words: 14L * levels + 8L * slots + 16L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(original) &&
    client_local_closed_carrier_proof_scratch_bytes() is Some(carrier) else {
    return None
  }
  @execution.checked_preparation_add_product(original, carrier, 1L)
}

///|
// The optional retained text-proof carrier remains alongside the same Plan.
// These are representation units, not additional admission/work allowances.
fn client_local_value_node_proof_retained_bytes() -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 2L,
    reference_slots: 3L,
    // Existing optional demand controls plus the immutable Carrier-mode bit.
    scalar_words: 5L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
fn client_local_json_contract_nodes(
  contract : @contract.Contract,
  work : Ref[Int],
  depth : Int,
) -> Int64? {
  if work.val < 1 || depth < 0 {
    return None
  }
  work.val -= 1
  match contract.shape {
    @contract.Number | @contract.Boolean | @contract.Text(_) => Some(1L)
    // Decimal admission and wire emission each use one successful value node.
    // This is NOT the text-free Number/Boolean proof: the existing256-byte
    // node envelope retains the Decimal record/coefficient; decoded input,
    // wire, CAST and aggregate workspace keep their independent old bounds.
    @contract.Decimal(..) => Some(1L)
    // The original Vector contract fixes every component's Number type and
    // dimension. Its JSON array is one node plus that many scalar nodes; the
    // Carrier provider still owns its separate vector storage/workspace.
    @contract.Vector(dimensions~) =>
      if dimensions >= 0.0 &&
        dimensions < 2147483647.0 &&
        dimensions.to_int().to_double() == dimensions {
        Some(1L + dimensions.to_int().to_int64())
      } else {
        None
      }
    // Opaque Resource values are not scalar JSON nodes. The SAME reference
    // owner bounds its admitted closed scalar envelope, including the object.
    // Content remains unbounded; no reference/issuer/current is consulted.
    @contract.ResourceRef(_) =>
      @admitted.reference_contract_value_node_bound(contract).map(Int::to_int64)
    @contract.Array(item, max_items~) => {
      guard max_items is Some(count) && count >= 0L else { return None }
      if count == 0L {
        return Some(1L)
      }
      guard client_local_json_contract_nodes(item, work, depth - 1)
        is Some(nodes) &&
        count <= (2147483647L - 1L) / nodes else {
        return None
      }
      Some(1L + count * nodes)
    }
    @contract.Object(fields) => {
      let mut nodes = 1L
      for index in 0..<@contract.field_count(fields) {
        guard @contract.field_at(fields, index) is Some(field) &&
          client_local_json_contract_nodes(field.contract, work, depth - 1)
          is Some(child) &&
          nodes <= 2147483647L - child else {
          return None
        }
        nodes += child
      }
      Some(nodes)
    }
    _ => None
  }
}

///|
fn client_local_json_schema_nodes(
  schema : @schema.Schema,
  max_work : Int,
  depth : Int,
) -> (Int64, Int)? {
  // The outer inventory already charged every root field. Only additional
  // nested contracts spend its remaining work; this is not Ledger work or a
  // physical refund. Keep the old leaf proof's exact exhausted-work behavior.
  let roots = @schema.field_count(schema)
  if max_work < 0 || roots > 2147483647 - max_work {
    return None
  }
  let work = Ref(max_work + roots)
  let mut nodes = 1L
  for index in 0..<@schema.field_count(schema) {
    guard @schema.field_at(schema, index) is Some(field) &&
      client_local_json_contract_nodes(
        @schema.field_contract(field),
        work,
        depth,
      )
      is Some(child) &&
      nodes <= 2147483647L - child else {
      return None
    }
    nodes += child
  }
  Some((nodes, max_work - work.val))
}

///|
/// Same-original node demand only: this does not prove numeric wire length,
/// remove text admission, or permit a different Program/Result inventory.
priv struct ClientLocalValueNodeDemand {
  original : ClientLocalSchemaProofInventory
  rows : Int
  nodes : Int
  // Once-computed optional checked Decimal text proof; never recomputed by a
  // Plan getter or promoted to an operation/physical admission.
  text_bound : Int?
}

///|
fn client_local_value_node_demand(
  original : ClientLocalSchemaProofInventory,
  rows : Int,
) -> ClientLocalValueNodeDemand? {
  match client_local_inventory_nodes(original, rows) {
    Some(nodes) => Some({ original, rows, nodes, text_bound: None, })
    None => None
  }
}
