///|
pub(all) enum SourceInputLogicalIssue {
  SourceInputWrongContract
  SourceInputIncomplete
  SourceInputOwnerMismatch(String)
  SourceInputInvalidOrdering
} derive(Eq, Debug)

///|
/// Match a sealed logical input to identities issued by the completed
/// capture owner and the checked source. The caller must hold that owner;
/// this CID by itself neither authorizes a read nor permits reacquisition.
pub fn admit_completed_source_input_logical(
  input : RunEvidenceValue,
  logical_relation_cid : String,
  relation_schema_cid : String,
  source_contract_cid : String,
  ordering_evidence_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SourceInputLogicalIssue] {
  if input.name != "source_input_logical" {
    return Err(SourceInputWrongContract)
  }
  if contract_string_from_value(input.value, "completeness") != Some("complete") {
    return Err(SourceInputIncomplete)
  }
  for
    (field, expected) in [
      ("logical_relation_cid", logical_relation_cid),
      ("relation_schema_cid", relation_schema_cid),
      ("source_contract_cid", source_contract_cid),
    ] {
    if contract_string_from_value(input.value, field) != Some(expected) {
      return Err(SourceInputOwnerMismatch(field))
    }
  }
  let ordering = match @json.object_field(input.value, "ordering_evidence") {
    Some(value) => value
    None => return Err(SourceInputInvalidOrdering)
  }
  let expected = match
    parse_contract_wire(
      ordering_evidence_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(SourceInputInvalidOrdering)
  }
  let actual_wire = @json.stringify_value(
    ordering, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(SourceInputInvalidOrdering)
  }
  let expected_wire = @json.stringify_value(
    expected, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(SourceInputInvalidOrdering)
  }
  if actual_wire != expected_wire {
    return Err(SourceInputInvalidOrdering)
  }
  Ok(input.identity)
}

///|
pub(all) enum SourceInputObservationIssue {
  WrongContract
  Incomplete
  Mismatch(String)
  InvalidOrdering
} derive(Eq, Debug)

///|
/// Bind an observed source to the completed logical input and the checked
/// source selected by the Host. The caller must separately retain the capture
/// owner and recheck current read authority; neither CID is a capability.
pub fn admit_completed_source_observation_binding(
  source : RunEvidenceValue,
  input : RunEvidenceValue,
  source_ref : String,
  source_contract_cid : String,
  authority_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SourceInputObservationIssue] {
  if source.name != "source_evidence" || input.name != "source_input_logical" {
    return Err(WrongContract)
  }
  if contract_string_from_value(source.value, "completeness") !=
    Some("complete") ||
    contract_string_from_value(input.value, "completeness") != Some("complete") {
    return Err(Incomplete)
  }
  for
    (field, expected) in [
      ("source_ref", source_ref),
      ("source_contract_cid", source_contract_cid),
      ("authority_scope_cid", authority_scope_cid),
      ("input_logical_cid", input.identity),
    ] {
    if contract_string_from_value(source.value, field) != Some(expected) {
      return Err(Mismatch(field))
    }
  }
  if contract_string_from_value(input.value, "source_contract_cid") !=
    Some(source_contract_cid) {
    return Err(Mismatch("input.source_contract_cid"))
  }
  let source_order = match
    @json.object_field(source.value, "ordering_evidence") {
    Some(value) => value
    None => return Err(InvalidOrdering)
  }
  let input_order = match @json.object_field(input.value, "ordering_evidence") {
    Some(value) => value
    None => return Err(InvalidOrdering)
  }
  let source_order_wire = @json.stringify_value(
    source_order, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidOrdering)
  }
  let input_order_wire = @json.stringify_value(
    input_order, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidOrdering)
  }
  if source_order_wire != input_order_wire {
    return Err(InvalidOrdering)
  }
  Ok(source.identity)
}
