///|
/// Admit a complete canonical Host-source wire witness against its expected
/// preimage CID and the exact admitted source Policy. Never trusts wire fields
/// as law, unit, numeric or dependency evidence independently of that Policy.
pub fn admit(
  bytes : Bytes,
  expected_cid : String,
  policy : @policy.Policy,
  limits : Limits,
) -> Result[Witness, Issue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) =>
      match e.issue {
        InputLimit | NodeLimit | DepthLimit => return Err(BudgetExceeded)
        _ => return Err(InvalidWitness)
      }
  }
  let cursor = match
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(v) => v
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.closed_object(cursor, [
      "version", "unit", "value", "role", "source", "law_id", "derivation", "dependencies",
      "witness_cid",
    ])
    is Ok(object) &&
    @decode.required(object, "witness_cid") is Ok(identity) &&
    @decode.text(identity) is Ok(identity) else {
    return Err(InvalidWitness)
  }
  if identity != expected_cid {
    return Err(IdentityMismatch)
  }
  guard @decode.required(object, "source") is Ok(source) &&
    @decode.closed_object(source, ["kind", "policy_cid", "field"]) is Ok(source) &&
    @decode.required(source, "field") is Ok(field) &&
    @decode.text(field) is Ok(field) else {
    return Err(InvalidWitness)
  }
  guard @policy.ceiling(policy, field) is Some(ceiling) else {
    return Err(UnsupportedPolicyField(field))
  }
  let witness = match create(ceiling, limits) {
    Ok(w) => w
    Err(e) => return Err(e)
  }
  if witness.cid != expected_cid {
    return Err(IdentityMismatch)
  }
  // Rebuild every member from the admitted policy, not from asserted wire
  // role/value/law/unit/source/dependencies. Full-byte identity also rejects
  // normalization repairs, alternate numeric spellings and extra whitespace.
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit(witness, writer)
    if @encode.finish_hash(writer) != @sha.hex(bytes) {
      return Err(InvalidWitness)
    }
    Ok(witness)
  } catch {
    _ => Err(BudgetExceeded)
  }
}
