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
  seal_completed_source_observation_owned(fields, None)
}

///|
// Data codec of the existing completed Source evidence, not a capture issuer.
// The Row Owner must supply exactly its captured-input order and custody.
pub(all) struct CompletedFileListingReportRow {
  row_ordinal : Int
  resource_ref_cid : String
  version : String?
  reported_media_type : String?
  media_type : String?
}

///|
/// Encode correlation from the same completed acquisition/capture Owner.
/// This API validates data only; an arbitrary row array proves no observation,
/// byte custody, current authority, publication ordering or physical funding.
pub fn seal_completed_file_listing_observation(
  fields : CompletedSourceObservationBody,
  row_count : Int,
  rows : Array[CompletedFileListingReportRow],
) -> Result[RunEvidenceValue, RunEvidenceValueIssue] {
  if row_count < 0 || row_count != rows.length() {
    return Err(RunEvidenceReferenceMismatch("file_listing_reports.row_count"))
  }
  // Every report requires at least one node. This is a necessary preflight
  // against the existing 256-node writer bound, not another count ceiling or
  // a physical grant. Refuse before an unbounded projection walk; the writer
  // still enforces the complete document's exact byte/node/depth limits.
  if rows.length() > 256 {
    return Err(RunEvidenceEncoding)
  }
  for index, row in rows {
    if row.row_ordinal != index || !valid_contract_cid(row.resource_ref_cid) {
      return Err(RunEvidenceReferenceMismatch("file_listing_reports.row"))
    }
    match (row.reported_media_type, row.media_type) {
      (None, None) => ()
      (Some(reported), Some(projected)) =>
        // The existing writer's finite wire bound is unchanged. Projection
        // preserves opaque data and is never a replacement for a missing report.
        if @contract.normalize_content_media_type_case(reported, 16384) !=
          Ok(projected) {
          return Err(
            RunEvidenceReferenceMismatch("file_listing_reports.media_type"),
          )
        }
      _ =>
        return Err(RunEvidenceReferenceMismatch("file_listing_reports.report"))
    }
  }
  seal_completed_source_observation_owned(fields, Some(rows))
}

///|
fn seal_completed_source_observation_owned(
  fields : CompletedSourceObservationBody,
  listing : Array[CompletedFileListingReportRow]?,
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
    if listing is Some(rows) {
      @encode.key(writer, "file_listing_reports")
      @encode.begin_object(writer)
      @encode.key(writer, "row_count")
      @encode.number_value(writer, rows.length().to_double())
      @encode.key(writer, "rows")
      @encode.begin_array(writer)
      for row in rows {
        @encode.begin_object(writer)
        @encode.key(writer, "row_ordinal")
        @encode.number_value(writer, row.row_ordinal.to_double())
        @encode.key(writer, "resource_ref_cid")
        @encode.string_value(writer, row.resource_ref_cid)
        emit_source_listing_nullable(writer, "version", row.version)
        emit_source_listing_nullable(
          writer,
          "reported_media_type",
          row.reported_media_type,
        )
        emit_source_listing_nullable(writer, "media_type", row.media_type)
        @encode.end_object(writer)
      }
      @encode.end_array(writer)
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(RunEvidenceEncoding)
  }
  seal_run_evidence_value("source_evidence", body, 16384, 256, 16)
}

///|
// Borrow each nullable scalar directly instead of allocating a three-entry
// tuple array for every report. This encoder has no retention/issuer authority.
fn emit_source_listing_nullable(
  writer : @encode.Writer,
  name : String,
  value : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  match value {
    Some(value) => @encode.string_value(writer, value)
    None => @encode.null_value(writer)
  }
}
