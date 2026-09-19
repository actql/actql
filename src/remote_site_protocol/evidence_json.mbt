///|
priv suberror EvidenceJsonStop {
  EvidenceJsonStop
}

///|
fn[T] evidence_decoded(
  value : Result[T, @decode.Issue],
) -> T raise EvidenceJsonStop {
  match value {
    Ok(result) => result
    Err(_) => raise EvidenceJsonStop
  }
}

///|
fn evidence_root(
  body : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @decode.Cursor raise EvidenceJsonStop {
  let bytes = @utf8.encode(body)
  if bytes.length() > max_bytes {
    raise EvidenceJsonStop
  }
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => raise EvidenceJsonStop
  }
  evidence_decoded(
    @decode.admit(node, {
      max_nodes,
      max_depth,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }),
  )
}

///|
fn evidence_object(
  root : @decode.Cursor,
  names : Array[String],
) -> @decode.ObjectView raise EvidenceJsonStop {
  evidence_decoded(@decode.closed_object(root, names))
}

///|
fn evidence_text(
  object : @decode.ObjectView,
  name : String,
) -> String raise EvidenceJsonStop {
  evidence_decoded(
    @decode.text(evidence_decoded(@decode.required(object, name))),
  )
}

///|
fn evidence_int(
  object : @decode.ObjectView,
  name : String,
) -> Int raise EvidenceJsonStop {
  let value = evidence_decoded(
    @decode.safe_integer(evidence_decoded(@decode.required(object, name))),
  )
  if value < 0L || value > 2147483647L {
    raise EvidenceJsonStop
  }
  value.to_int()
}

///|
fn evidence_text_int64(
  object : @decode.ObjectView,
  name : String,
) -> Int64 raise EvidenceJsonStop {
  let text = evidence_text(object, name)
  match @scalar.read_decimal_int64(text) {
    Ok(value) if value >= 0L && value.to_string() == text => value
    _ => raise EvidenceJsonStop
  }
}

///|
/// Re-admits one canonical Site execution evidence body. Transport JSON is
/// not trusted as identity merely because it was stored or authenticated.
pub fn admit_remote_execution_evidence_json(
  body : String,
  claimed_cid : String,
  request : DispatchRequest,
) -> Result[RemoteExecutionEvidence, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 65536, 32, 2), [
      "connector_registration", "connector_revision", "dispatch_request_cid", "evidence_kind",
      "evidence_subject_cid", "holding_evidence_cid", "issuer_capability_cid", "material_generation",
      "obligations_cid", "runtime_bundle_cid", "site_generation", "site_key", "strategy_revision",
      "version",
    ])
    if evidence_text(object, "version") != "actql-remote-execution-evidence/0.1" {
      raise EvidenceJsonStop
    }
    let evidence = match
      admit_remote_execution_evidence(
        evidence_text(object, "connector_registration"),
        evidence_text(object, "connector_revision"),
        evidence_text(object, "dispatch_request_cid"),
        evidence_text(object, "evidence_kind"),
        evidence_text(object, "evidence_subject_cid"),
        evidence_text(object, "holding_evidence_cid"),
        evidence_text(object, "issuer_capability_cid"),
        evidence_text(object, "material_generation"),
        evidence_text(object, "obligations_cid"),
        evidence_text(object, "runtime_bundle_cid"),
        evidence_int(object, "site_generation"),
        evidence_text(object, "site_key"),
        evidence_text(object, "strategy_revision"),
        claimed_cid,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if !remote_execution_evidence_matches_dispatch(evidence, request) ||
      remote_execution_evidence_json(evidence) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok(evidence)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
/// Re-admits one canonical managed-output subject for the exact dispatch.
pub fn admit_remote_managed_output_subject_json(
  body : String,
  claimed_cid : String,
  request : DispatchRequest,
) -> Result[RemoteManagedOutputSubject, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 65536, 32, 2), [
      "dispatch_request_cid", "holding_evidence_cid", "logical_view_cid", "managed_profile_cid",
      "material_generation", "measurement_evidence_cid", "physical_manifest_cid",
      "representation_codec_cid", "result_schema_cid", "retained_bytes", "row_count",
      "version",
    ])
    if evidence_text(object, "version") !=
      "actql-remote-managed-output-subject/0.2" {
      raise EvidenceJsonStop
    }
    let subject = match
      admit_remote_managed_output_subject(
        evidence_text(object, "dispatch_request_cid"),
        evidence_text(object, "material_generation"),
        evidence_text(object, "holding_evidence_cid"),
        evidence_text(object, "managed_profile_cid"),
        evidence_text(object, "result_schema_cid"),
        evidence_text(object, "logical_view_cid"),
        evidence_text(object, "representation_codec_cid"),
        evidence_text(object, "physical_manifest_cid"),
        evidence_text(object, "measurement_evidence_cid"),
        evidence_int(object, "row_count"),
        evidence_text_int64(object, "retained_bytes"),
        claimed_cid,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if !remote_managed_output_subject_matches_dispatch(subject, request) ||
      remote_managed_output_subject_json(subject) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok(subject)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
/// Re-admits one canonical managed-output measurement body.
pub fn admit_remote_managed_output_measurement_json(
  body : String,
  claimed_cid : String,
) -> Result[RemoteManagedOutputMeasurement, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 262144, 65536, 3), [
      "admission_nodes", "admission_text_bytes", "admission_work", "columns", "row_count",
      "version",
    ])
    if evidence_text(object, "version") !=
      "actql-remote-managed-output-measurement/0.1" {
      raise EvidenceJsonStop
    }
    let columns = evidence_decoded(@decode.required(object, "columns"))
    let width = match @decode.array_length(columns) {
      Some(value) if value <= 4096 => value
      _ => raise EvidenceJsonStop
    }
    let column_rows = []
    let column_bytes = []
    let column_nodes = []
    let column_max_value_bytes = []
    let column_null_rows = []
    let column_admitted_depths = []
    for index in 0..<width {
      let column = evidence_object(
        @decode.element_at(columns, index).unwrap(),
        [
          "admitted_depth", "bytes", "max_value_bytes", "nodes", "null_rows", "rows",
        ],
      )
      column_rows.push(evidence_int(column, "rows"))
      column_bytes.push(evidence_int(column, "bytes"))
      column_nodes.push(evidence_int(column, "nodes"))
      column_max_value_bytes.push(evidence_int(column, "max_value_bytes"))
      column_null_rows.push(evidence_int(column, "null_rows"))
      column_admitted_depths.push(evidence_int(column, "admitted_depth"))
    }
    let measurement = match
      admit_remote_managed_output_measurement(
        evidence_int(object, "row_count"),
        evidence_int(object, "admission_nodes"),
        evidence_int(object, "admission_text_bytes"),
        evidence_int(object, "admission_work"),
        column_rows,
        column_bytes,
        column_nodes,
        column_max_value_bytes,
        column_null_rows,
        column_admitted_depths,
        claimed_cid,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if remote_managed_output_measurement_json(measurement) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok(measurement)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}
