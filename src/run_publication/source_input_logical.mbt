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
  if contract_string_from_value(input.value, "completeness") !=
    Some("complete") {
    return Err(SourceInputIncomplete)
  }
  for (field, expected) in [
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
