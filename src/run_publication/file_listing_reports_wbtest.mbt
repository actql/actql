///|
// These fixed bodies/CIDs are independently calculated in the checked corpus.
// The synthetic data codec proves no actual Row/capture custody or funding.
fn listing_report_codec_fields(source_ref : String) -> CompletedSourceObservationBody {
  {
    input: seal_run_evidence_value("source_input_logical", "{\"completeness\":\"complete\",\"logical_relation_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"ordering_evidence\":{\"keys\":[],\"stable\":false},\"relation_schema_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"source_contract_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"version\":\"actql-source-input-logical/0.1\"}", 4096, 128, 16).unwrap(),
    source_ref,
    source_contract_cid: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    schema_evidence_cid: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    capability_evidence_cid: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    authority_scope_cid: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    source_data_policy_cid: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    data_classification: "internal",
    source_view_contract_cid: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    observed_at: "2026-10-13T00:00:00.000Z",
    snapshot_ref: "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  }
}

///|
fn listing_report_codec_row(reported : String?, projected : String?) -> CompletedFileListingReportRow {
  { row_ordinal: 0, resource_ref_cid: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    version: Some("9007199254740993"), reported_media_type: reported, media_type: projected }
}

///|
fn listing_report_codec_body(value : RunEvidenceValue) -> String {
  let body = @json.object_without_field(value.value, "source_evidence_cid").unwrap()
  @json.stringify_value(body, 16384, 256, 16) catch {
    _ => abort("fixed listing codec body")
  }
}

///|
test "completed listing report codec fixed non-listing bytes and identity" {
  let value = seal_completed_source_observation(listing_report_codec_fields("connector://crm/main/r#v")).unwrap()
  assert_eq(listing_report_codec_body(value), "{\"authority_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"capability_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"completeness\":\"complete\",\"consistency_level\":\"read_committed\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"input_logical_cid\":\"sha256:f1a3aa72b6b2c84a2c9d0a07fa1b10d7ec8986ec8db32586f0bd8210287bbc0c\",\"observed_at\":\"2026-10-13T00:00:00.000Z\",\"ordering_evidence\":{\"keys\":[],\"stable\":false},\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"schema_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"snapshot_ref\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"source_contract_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"source_ref\":\"connector://crm/main/r#v\",\"source_view_contract_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"version\":\"actql-source-evidence/0.1\"}")
  assert_eq(run_evidence_value_identity(value), "sha256:bc7dc16b6de51a07a3bfdfeeca311da581c9e2fe35fee66f21883a80fb98b27d")
  let saved = admit_run_evidence_value("source_evidence", run_evidence_value_json(value), 16384, 256, 16).unwrap()
  assert_eq(run_evidence_value_identity(saved), "sha256:bc7dc16b6de51a07a3bfdfeeca311da581c9e2fe35fee66f21883a80fb98b27d")
}

///|
test "completed listing report codec fixed empty-listing bytes and identity" {
  let value = seal_completed_file_listing_observation(listing_report_codec_fields("connector://gcs/dev/files#records"), 0, []).unwrap()
  assert_eq(listing_report_codec_body(value), "{\"authority_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"capability_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"completeness\":\"complete\",\"consistency_level\":\"read_committed\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"file_listing_reports\":{\"row_count\":0,\"rows\":[]},\"input_logical_cid\":\"sha256:f1a3aa72b6b2c84a2c9d0a07fa1b10d7ec8986ec8db32586f0bd8210287bbc0c\",\"observed_at\":\"2026-10-13T00:00:00.000Z\",\"ordering_evidence\":{\"keys\":[],\"stable\":false},\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"schema_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"snapshot_ref\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"source_contract_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"source_ref\":\"connector://gcs/dev/files#records\",\"source_view_contract_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"version\":\"actql-source-evidence/0.1\"}")
  assert_eq(run_evidence_value_identity(value), "sha256:af1a935647e82685b5beef7b7267150ad73bdbc23b188ae5cf1da543447e9566")
  let saved = admit_run_evidence_value("source_evidence", run_evidence_value_json(value), 16384, 256, 16).unwrap()
  assert_eq(run_evidence_value_identity(saved), "sha256:af1a935647e82685b5beef7b7267150ad73bdbc23b188ae5cf1da543447e9566")
}

///|
test "completed listing report codec fixed null bytes and identity" {
  let value = seal_completed_file_listing_observation(listing_report_codec_fields("connector://gcs/dev/files#records"), 1, [listing_report_codec_row(None, None)]).unwrap()
  assert_eq(listing_report_codec_body(value), "{\"authority_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"capability_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"completeness\":\"complete\",\"consistency_level\":\"read_committed\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"file_listing_reports\":{\"row_count\":1,\"rows\":[{\"media_type\":null,\"reported_media_type\":null,\"resource_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_ordinal\":0,\"version\":\"9007199254740993\"}]},\"input_logical_cid\":\"sha256:f1a3aa72b6b2c84a2c9d0a07fa1b10d7ec8986ec8db32586f0bd8210287bbc0c\",\"observed_at\":\"2026-10-13T00:00:00.000Z\",\"ordering_evidence\":{\"keys\":[],\"stable\":false},\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"schema_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"snapshot_ref\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"source_contract_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"source_ref\":\"connector://gcs/dev/files#records\",\"source_view_contract_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"version\":\"actql-source-evidence/0.1\"}")
  assert_eq(run_evidence_value_identity(value), "sha256:ffb0472c800e8b0359db5cc55d2c791077953e8f1d934653753f79f1c74f9059")
  let saved = admit_run_evidence_value("source_evidence", run_evidence_value_json(value), 16384, 256, 16).unwrap()
  assert_eq(run_evidence_value_identity(saved), "sha256:ffb0472c800e8b0359db5cc55d2c791077953e8f1d934653753f79f1c74f9059")
}

///|
test "completed listing report codec fixed nfd bytes and identity" {
  let value = seal_completed_file_listing_observation(listing_report_codec_fields("connector://gcs/dev/files#records"), 1, [listing_report_codec_row(Some("Text/Plain;Label=\"é\""), Some("text/plain;label=\"é\""))]).unwrap()
  assert_eq(listing_report_codec_body(value), "{\"authority_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"capability_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"completeness\":\"complete\",\"consistency_level\":\"read_committed\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"file_listing_reports\":{\"row_count\":1,\"rows\":[{\"media_type\":\"text/plain;label=\\\"é\\\"\",\"reported_media_type\":\"Text/Plain;Label=\\\"é\\\"\",\"resource_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_ordinal\":0,\"version\":\"9007199254740993\"}]},\"input_logical_cid\":\"sha256:f1a3aa72b6b2c84a2c9d0a07fa1b10d7ec8986ec8db32586f0bd8210287bbc0c\",\"observed_at\":\"2026-10-13T00:00:00.000Z\",\"ordering_evidence\":{\"keys\":[],\"stable\":false},\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"schema_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"snapshot_ref\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"source_contract_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"source_ref\":\"connector://gcs/dev/files#records\",\"source_view_contract_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"version\":\"actql-source-evidence/0.1\"}")
  assert_eq(run_evidence_value_identity(value), "sha256:1d7f15a34edb53acc3d6593a44647c36f20e91de2f19a8eff3d2c883ccb4b033")
  let saved = admit_run_evidence_value("source_evidence", run_evidence_value_json(value), 16384, 256, 16).unwrap()
  assert_eq(run_evidence_value_identity(saved), "sha256:1d7f15a34edb53acc3d6593a44647c36f20e91de2f19a8eff3d2c883ccb4b033")
}

///|
test "completed listing report codec fixed nfc bytes and identity" {
  let value = seal_completed_file_listing_observation(listing_report_codec_fields("connector://gcs/dev/files#records"), 1, [listing_report_codec_row(Some("Text/Plain;Label=\"é\""), Some("text/plain;label=\"é\""))]).unwrap()
  assert_eq(listing_report_codec_body(value), "{\"authority_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"capability_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"completeness\":\"complete\",\"consistency_level\":\"read_committed\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"file_listing_reports\":{\"row_count\":1,\"rows\":[{\"media_type\":\"text/plain;label=\\\"é\\\"\",\"reported_media_type\":\"Text/Plain;Label=\\\"é\\\"\",\"resource_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_ordinal\":0,\"version\":\"9007199254740993\"}]},\"input_logical_cid\":\"sha256:f1a3aa72b6b2c84a2c9d0a07fa1b10d7ec8986ec8db32586f0bd8210287bbc0c\",\"observed_at\":\"2026-10-13T00:00:00.000Z\",\"ordering_evidence\":{\"keys\":[],\"stable\":false},\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"schema_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"snapshot_ref\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"source_contract_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source_data_policy_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"source_ref\":\"connector://gcs/dev/files#records\",\"source_view_contract_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"version\":\"actql-source-evidence/0.1\"}")
  assert_eq(run_evidence_value_identity(value), "sha256:22f53c988762618c5eafadb9bb0d155d0c16b64884661cd6428874c96c83a35f")
  let saved = admit_run_evidence_value("source_evidence", run_evidence_value_json(value), 16384, 256, 16).unwrap()
  assert_eq(run_evidence_value_identity(saved), "sha256:22f53c988762618c5eafadb9bb0d155d0c16b64884661cd6428874c96c83a35f")
}

///|
test "completed listing report codec rejects count ordinal and missing report pairing" {
  let fields = listing_report_codec_fields("connector://gcs/dev/files#records")
  let row = listing_report_codec_row(Some("Text/Plain"), Some("text/plain"))
  assert_true(seal_completed_file_listing_observation(fields, 2, [row]) is Err(_))
  assert_true(seal_completed_file_listing_observation(fields, 1, [{ ..row, row_ordinal: 1 }]) is Err(_))
  assert_true(seal_completed_file_listing_observation(fields, 1, [{ ..row, media_type: None }]) is Err(_))
  assert_true(seal_completed_file_listing_observation(fields, 1, [{ ..row, reported_media_type: None }]) is Err(_))
  assert_true(seal_completed_file_listing_observation(fields, 1, [{ ..row, media_type: Some("Text/Plain") }]) is Err(_))
  assert_true(seal_completed_file_listing_observation(fields, 1, [{ ..row, resource_ref_cid: "foreign" }]) is Err(_))
}

///|
test "listing report reader rejects schema-valid reordered or inconsistent correlation" {
  let fields = listing_report_codec_fields("connector://gcs/dev/files#records")
  let value = seal_completed_file_listing_observation(fields, 1,
    [listing_report_codec_row(Some("Text/Plain"), Some("text/plain"))]).unwrap()
  let body = listing_report_codec_body(value)
  for (old, new) in [
    ("\"row_count\":1", "\"row_count\":2"),
    ("\"row_ordinal\":0", "\"row_ordinal\":1"),
    ("\"media_type\":\"text/plain\"", "\"media_type\":null"),
  ] {
    assert_true(seal_run_evidence_value("source_evidence", body.replace(old~, new~), 16384, 256, 16)
      is Err(RunEvidenceReferenceMismatch("file_listing_reports")))
  }
}

///|
test "listing report writer retains existing finite encoding bounds" {
  let fields = listing_report_codec_fields("connector://gcs/dev/files#records")
  let row = listing_report_codec_row(None, None)
  let rows = Array::makei(100, i => { ..row, row_ordinal: i })
  assert_true(seal_completed_file_listing_observation(fields, 100, rows) is Err(_))
}
