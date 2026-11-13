///|
/// Reuse the already-backed canonical value for the closed Compiled Plan.
/// This is the same full shape, identity and canonical emission admission as
/// the wire reader; it never creates a checked compilation or Run authority.
pub fn admit_saved_compiled_plan_value(
  wire : String,
  value : @json.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  let admitted = admit_publication_contract_material(
    contract_spec("compiled_plan").unwrap(),
    value,
    wire,
    max_bytes,
    max_nodes,
    max_depth,
  )
  match admitted {
    Ok(value) if value.wire == wire => Ok(value)
    Ok(_) => Err(InvalidWire)
    Err(issue) => Err(issue)
  }
}

///|
/// Compare fields borrowed from the admitted immutable owners, not reparsed
/// wire copies. This checks correspondence only, never access or execution.
pub fn saved_compiled_plan_matches_definition(
  plan : PublicationContract,
  definition : PublicationContract,
  program_cid : String?,
) -> Bool {
  if plan.name != "compiled_plan" ||
    definition.name != "run_definition" ||
    contract_string(definition, "compiled_plan_cid") != Some(plan.identity) {
    return false
  }
  guard contract_string(plan, "program_definition_cid") is Some(actual) else {
    return false
  }
  match program_cid {
    Some(expected) => actual == expected
    None => true
  }
}

///|
/// Closed compiled_plan field-rule/identity-preimage constructor DATA. The
/// codec owns parser, canonical tree, hash, text writer and their controls.
/// Malformed object widths are bounded by the measured node count before
/// shape rejection; valid identity preimages contain at most nine fields.
pub fn saved_compiled_plan_validation_construction(
  nodes : Int,
) -> @shape.CollectionConstructionExtent? {
  if nodes < 1 {
    return None
  }
  let n = nodes.to_int64()
  @shape.collection_construction_extent({
    // Eight field/rule records, ContractSpec/Some, detached field tuples,
    // allowed-key Array, identity-preimage tuples and root/FrozenArray.
    records: 8L + 8L + 2L + n + 9L + 2L + 8L,
    record_references: 3L * 8L + 8L + 5L + 2L * n + 2L * 9L + 2L + 8L,
    record_words: 8L,
    // Include the bounded-contract canonical-wire name selector and the
    // empty default nested-artifact inventory from the same admission call.
    reference_arrays: 4L + 1L + 1L,
    reference_items: 8L + n + 10L + 9L + 13L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}
