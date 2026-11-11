///|
/// Exact old acceptance facts captured at explicit upgrade. This metadata is
/// not current authority, an accepted new Run or permission to replay work.
pub(all) struct ClientLocalLegacyPolicyRun {
  request_scope_cid : String
  run_definition_cid : String
  submission_reference_cid : String
  admitted_revision : Int64
} derive(Eq, Debug)

///|
struct ClientLocalRunPolicyUpgrade {
  body : Bytes
  read_wire : String
  legacy : Array[ClientLocalLegacyPolicyRun]
}

///|
fn local_policy_upgrade_keys() -> Array[String] {
  [
    "adoption_cid", "authority_scope_cid", "legacy_admissions_wire", "operation_id",
    "profile_wire", "read_configuration_name", "read_original_cid", "read_selection_wire",
    "retention_configuration_cid", "retention_configuration_name", "run_configuration_cid",
    "run_configuration_name", "store_configuration_cid", "store_configuration_name",
    "version",
  ]
}

///|
fn local_policy_upgrade_name(text : String) -> Bool {
  !text.is_empty() &&
  text.length() <= 128 &&
  text != "." &&
  text != ".." &&
  !text.contains("/") &&
  !text.contains("\\") &&
  !text.contains("\u{0000}")
}

///|
// Preserve every disclosure value. Only the explicit lifetime alternative is
// changed; Native must first admit the original through its read Policy Owner.
pub fn client_local_finite_read_selection_wire(
  original_wire : String,
  profile : ClientLocalRunPolicyProfile,
  run_file : String,
  retention_file : String,
  store_file : String,
) -> Result[String, ClientLocalRunPolicyProfileIssue] {
  if ![run_file, retention_file, store_file].all(local_policy_upgrade_name) ||
    run_file == retention_file ||
    run_file == store_file ||
    retention_file == store_file {
    return Err(InvalidOriginal)
  }
  guard run_profile_value(original_wire) is Some(original) &&
    @canonical.object_field_count(original) == Some(2) &&
    run_profile_text(original, "version") == Some("actql-config/0.1") &&
    @canonical.object_field(original, "native") is Some(native) &&
    @canonical.object_field_count(native) == Some(1) &&
    @canonical.object_field(native, "result_read") is Some(read) &&
    @canonical.object_fields(read) is Some(fields) &&
    fields.length() == 11 &&
    fields.all(field => {
      [
        "enabled", "principal", "connection", "result_names", "formats", "purpose",
        "sink", "data_policy_cids", "accepted_run_policy", "max_bytes", "max_uses",
        "expires_at",
      ].contains(field.0)
    }) &&
    (match
      (
        @canonical.object_field(read, "data_policy_cids"),
        @canonical.object_field(read, "accepted_run_policy"),
      ) {
      (Some(_), None) | (None, Some(@canonical.Bool(true))) => true
      _ => false
    }) &&
    run_profile_text(read, "expires_at") is Some(expiry) &&
    @values.timestamp_epoch_milliseconds(expiry) is Some(_) &&
    @canonical.object_without_field(read, "expires_at") is Some(without) &&
    @canonical.object_with_string_field(
      without,
      "run_policy_profile_cid",
      client_local_run_policy_profile_cid(profile),
    )
    is Some(profile_bound) &&
    @canonical.object_with_string_field(profile_bound, "run_file", run_file)
    is Some(run_bound) &&
    @canonical.object_with_string_field(
      run_bound, "retention_file", retention_file,
    )
    is Some(retention_bound) &&
    @canonical.object_with_string_field(
      retention_bound, "store_file", store_file,
    )
    is Some(finite) else {
    return Err(InvalidOriginal)
  }
  try {
    let writer = @encode.writer(8192, 256, 8)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "native")
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "result_read")
    @canonical.emit_value(finite, writer)
    @encode.end_object(writer)
    @encode.ordered_key(writer, "version")
    @encode.string_value(writer, "actql-config/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn local_policy_legacy_wire(
  records : Array[ClientLocalLegacyPolicyRun],
) -> Result[String, ClientLocalRunPolicyProfileIssue] {
  if records.length() > 8 {
    return Err(Encoding)
  }
  let records = records.copy()
  records.sort_by((a, b) => a.request_scope_cid.compare(b.request_scope_cid))
  for index, record in records {
    if record.admitted_revision < 0L ||
      ![
        record.request_scope_cid,
        record.run_definition_cid,
        record.submission_reference_cid,
      ].all(local_run_policy_original_cid) ||
      (
        index > 0 &&
        records[index - 1].request_scope_cid == record.request_scope_cid
      ) {
      return Err(InvalidOriginal)
    }
  }
  try {
    let writer = @encode.writer(4096, 64, 4)
    @encode.begin_array(writer)
    for record in records {
      @encode.begin_ordered_object(writer)
      @encode.ordered_key(writer, "admitted_revision")
      @encode.string_value(writer, record.admitted_revision.to_string())
      @encode.ordered_key(writer, "request_scope_cid")
      @encode.string_value(writer, record.request_scope_cid)
      @encode.ordered_key(writer, "run_definition_cid")
      @encode.string_value(writer, record.run_definition_cid)
      @encode.ordered_key(writer, "submission_reference_cid")
      @encode.string_value(writer, record.submission_reference_cid)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn local_policy_read_legacy(
  wire : String,
) -> Result[Array[ClientLocalLegacyPolicyRun], ClientLocalRunPolicyProfileIssue] {
  guard @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 4096,
      max_nodes: 64,
      max_depth: 4,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes: 64,
      max_depth: 4,
      max_string_bytes: 71,
      max_total_string_bytes: 4096,
    })
    is Ok(cursor) &&
    @decode.elements(cursor) is Ok(values) &&
    values.length() <= 8 else {
    return Err(InvalidOriginal)
  }
  let records : Array[ClientLocalLegacyPolicyRun] = []
  for value in values {
    guard @decode.closed_object(value, [
        "admitted_revision", "request_scope_cid", "run_definition_cid", "submission_reference_cid",
      ])
      is Ok(object) &&
      @decode.lookup(object, "admitted_revision") is Some(revision) &&
      @decode.decimal_int64(revision) is Ok(admitted_revision) &&
      admitted_revision >= 0L &&
      @decode.lookup(object, "request_scope_cid") is Some(request) &&
      @decode.text(request) is Ok(request_scope_cid) &&
      @decode.lookup(object, "run_definition_cid") is Some(run) &&
      @decode.text(run) is Ok(run_definition_cid) &&
      @decode.lookup(object, "submission_reference_cid") is Some(reference) &&
      @decode.text(reference) is Ok(submission_reference_cid) else {
      return Err(InvalidOriginal)
    }
    records.push({
      request_scope_cid,
      run_definition_cid,
      submission_reference_cid,
      admitted_revision,
    })
  }
  if local_policy_legacy_wire(records) != Ok(wire) {
    return Err(InvalidOriginal)
  }
  Ok(records)
}

///|
/// Bind existing selected originals and the exact legacy acceptance set.
/// Native authenticates and commits this once in its existing installation
/// journal/capacity transaction. Parsing this body grants no such custody.
pub fn bind_client_local_run_policy_upgrade(
  profile : ClientLocalRunPolicyProfile,
  original_read_wire : String,
  adoption_cid : String,
  authority_scope_cid : String,
  operation_id : String,
  selected : Array[(String, String)],
  legacy : Array[ClientLocalLegacyPolicyRun],
) -> Result[ClientLocalRunPolicyUpgrade, ClientLocalRunPolicyProfileIssue] {
  if !local_run_policy_original_cid(adoption_cid) ||
    !local_run_policy_original_cid(authority_scope_cid) ||
    operation_id.is_empty() ||
    operation_id.length() > 128 ||
    operation_id.contains("\u{0000}") ||
    selected.length() != 4 {
    return Err(InvalidOriginal)
  }
  for index, file in selected {
    if !local_policy_upgrade_name(file.0) ||
      !local_run_policy_original_cid(file.1) {
      return Err(InvalidOriginal)
    }
    for prior in 0..<index {
      if selected[prior].0 == file.0 {
        return Err(InvalidOriginal)
      }
    }
  }
  if selected[0].1 != product_cid(original_read_wire) {
    return Err(InvalidOriginal)
  }
  let read_wire = match
    client_local_finite_read_selection_wire(
      original_read_wire,
      profile,
      selected[1].0,
      selected[2].0,
      selected[3].0,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let legacy_wire = match local_policy_legacy_wire(legacy) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = match
    client_local_original_record_body([
      ("adoption_cid", adoption_cid),
      ("authority_scope_cid", authority_scope_cid),
      ("legacy_admissions_wire", legacy_wire),
      ("operation_id", operation_id),
      ("profile_wire", profile.wire),
      ("read_configuration_name", selected[0].0),
      ("read_original_cid", selected[0].1),
      ("read_selection_wire", read_wire),
      ("retention_configuration_cid", selected[2].1),
      ("retention_configuration_name", selected[2].0),
      ("run_configuration_cid", selected[1].1),
      ("run_configuration_name", selected[1].0),
      ("store_configuration_cid", selected[3].1),
      ("store_configuration_name", selected[3].0),
      ("version", "actql-local-run-policy-upgrade/0.1"),
    ]) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let saved_legacy = match local_policy_read_legacy(legacy_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ body, read_wire, legacy: saved_legacy, })
}

///|
/// Validate the stored upgrade against original adoption/selected bodies.
/// The saved legacy set and operation identity are immutable, not recaptured.
pub fn admit_client_local_run_policy_upgrade(
  body : Bytes,
  profile : ClientLocalRunPolicyProfile,
  original_read_wire : String,
  adoption_cid : String,
  authority_scope_cid : String,
  operation_id : String,
  selected : Array[(String, String)],
) -> Result[ClientLocalRunPolicyUpgrade, ClientLocalRunPolicyProfileIssue] {
  let fields = match
    client_local_original_record_fields(body, local_policy_upgrade_keys()) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  let legacy = match local_policy_read_legacy(fields[2]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  bind_client_local_run_policy_upgrade(
    profile, original_read_wire, adoption_cid, authority_scope_cid, operation_id,
    selected, legacy,
  ).bind(original => {
    if original.body == body {
      Ok(original)
    } else {
      Err(InvalidOriginal)
    }
  })
}

///|
pub fn client_local_run_policy_upgrade_body(
  original : ClientLocalRunPolicyUpgrade,
) -> Bytes {
  original.body
}

///|
pub fn client_local_run_policy_upgrade_read_wire(
  original : ClientLocalRunPolicyUpgrade,
) -> String {
  original.read_wire
}

///|
pub fn client_local_run_policy_upgrade_legacy_runs(
  original : ClientLocalRunPolicyUpgrade,
) -> Array[ClientLocalLegacyPolicyRun] {
  original.legacy.copy()
}
