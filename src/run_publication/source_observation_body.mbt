///|
/// Codec inputs from an existing completed acquisition owner. These fields
/// are not custody, current read authority, or a provider completion proof.
pub(all) struct CompletedSourceObservationBody {
  input : RunEvidenceValue
  source_ref : String
  source_contract_cid : String
  schema_evidence_cid : String
  capability_evidence_cid : String
  authority_scope_cid : String
  source_data_policy_cid : String
  data_classification : String
  source_view_contract_cid : String
  observed_at : String
  snapshot_ref : String
}

///|
/// Share the existing snapshot/read-committed Source wire codec. Callers must
/// prove their own exact capture tuple and current authority before encoding.
/// A selected-key observation does not imply a full provider snapshot.
pub fn seal_completed_source_observation(
  fields : CompletedSourceObservationBody,
) -> Result[RunEvidenceValue, RunEvidenceValueIssue] {
  let input = fields.input
  if input.name != "source_input_logical" ||
    contract_string_from_value(input.value, "completeness") != Some("complete") ||
    contract_string_from_value(input.value, "source_contract_cid") !=
    Some(fields.source_contract_cid) {
    return Err(RunEvidenceReferenceMismatch("source_input"))
  }
  let writer = @encode.writer(16384, 256, 16) catch {
    _ => return Err(RunEvidenceEncoding)
  }
  let body = try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("version", "actql-source-evidence/0.1"),
        ("source_ref", fields.source_ref),
        ("input_logical_cid", input.identity),
        ("source_contract_cid", fields.source_contract_cid),
        ("schema_evidence_cid", fields.schema_evidence_cid),
        ("capability_evidence_cid", fields.capability_evidence_cid),
        ("authority_scope_cid", fields.authority_scope_cid),
        ("source_data_policy_cid", fields.source_data_policy_cid),
        ("effective_data_policy_cid", fields.source_data_policy_cid),
        ("data_classification", fields.data_classification),
        ("source_view_contract_cid", fields.source_view_contract_cid),
        ("output_carrier", "relation"),
        ("read_mode", "snapshot"),
        ("observed_at", fields.observed_at),
        ("snapshot_ref", fields.snapshot_ref),
        ("completeness", "complete"),
        ("consistency_level", "read_committed"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "ordering_evidence")
    @encode.begin_object(writer)
    @encode.key(writer, "stable")
    @encode.bool_value(writer, false)
    @encode.key(writer, "keys")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(RunEvidenceEncoding)
  }
  seal_run_evidence_value("source_evidence", body, 16384, 256, 16)
}
