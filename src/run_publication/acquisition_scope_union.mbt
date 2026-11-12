///|
/// Combine only the request inventory from admitted acquisition scopes. This
/// envelope neither grants access nor attests that any acquisition occurred;
/// the caller must retain the captured observations proving each dependency.
/// Duplicate requests share one canonical entry. Limits cover all input entries,
/// including duplicates, before the bounded inventory is sorted and encoded.
pub fn issue_combined_acquisition_scope(
  scopes : Array[PublicationContract],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[PublicationContract, AcquisitionRelationIssue] {
  if scopes.is_empty() {
    return Err(WrongScope)
  }
  if max_nodes < scopes.length() {
    return Err(Encoding)
  }
  let mut remaining = max_nodes - scopes.length()
  let entries : Map[String, @json.CanonicalValue] = Map([])
  let keys : Array[String] = []
  for scope in scopes {
    guard scope.name == "acquisition_scope" &&
      @json.object_field(scope.value, "sources") is Some(@json.Array(array)) else {
      return Err(WrongScope)
    }
    for entry in @json.array_values(array) {
      if remaining == 0 {
        return Err(Encoding)
      }
      remaining -= 1
      let source = evidence_string(entry, "source_contract_cid").unwrap()
      let values = @json.object_field(entry, "request_values_cid")
        .bind(scope_optional_cid)
        .unwrap()
      let request_keys = @json.object_field(entry, "request_key_set_cid")
        .bind(scope_optional_cid)
        .unwrap()
      // Same ordering as the admitted 0.1 scope validator, including nulls.
      let key = request_keys + "," + values + "," + source
      if !entries.contains(key) {
        entries[key] = entry
        keys.push(key)
      }
    }
  }
  keys.sort_by(@canonical.compare_utf16)
  if before_body is Some(back) {
    let measure = @encode.construction_measuring_writer(
      max_bytes, max_nodes, max_depth,
    ) catch {
      _ => return Err(Encoding)
    }
    let shape = try {
      emit_acquisition_scope_body(measure, writer => {
        for key in keys {
          @json.emit_value(entries[key], writer)
        }
      })
      @encode.finish_construction_measurement(measure)
    } catch {
      _ => {
        @encode.cancel_writer(measure)
        return Err(Encoding)
      }
    }
    if !back("acquisition_scope", shape) {
      return Err(Encoding)
    }
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_acquisition_scope_body(writer, writer => {
    for key in keys {
      @json.emit_value(entries[key], writer)
    }
  }) catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  seal_publication_contract(
    "acquisition_scope", body, max_bytes, max_nodes, max_depth,
  ).map_err(issue => AcquisitionRelationIssue::Contract(issue))
}

///|
/// Before-construction body facts for the SAME Source Unit metadata emitters.
/// Source/read/Request/Run provenance stays with the calling original owner.
/// The final union is bounded by all original entries before deduplication;
/// future CID positions use an admitted CID's fixed width, never a new identity.
pub fn source_unit_metadata_construction_geometry(
  sources : Array[RunEvidenceValue],
  inputs : Array[RunEvidenceValue],
  rows : Array[Int],
  retention : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  include_union? : Bool = true,
) -> Result[
  Array[(String, @encode.EncodingConstructionGeometry)],
  AcquisitionRelationIssue,
] {
  if sources.is_empty() ||
    sources.length() > max_nodes ||
    sources.length() != inputs.length() ||
    sources.length() != rows.length() ||
    retention.name != "result_retention_policy" {
    return Err(WrongEvidence)
  }
  let bodies : Array[(String, @encode.EncodingConstructionGeometry)] = []
  let mut active : @encode.Writer? = None
  try {
    for index, source in sources {
      let input = inputs[index]
      if source.name != "source_evidence" ||
        input.name != "source_input_logical" ||
        rows[index] < 0 {
        return Err(WrongEvidence)
      }
      let producer = evidence_string(source.value, "source_contract_cid").unwrap()
      let policy = evidence_string(source.value, "effective_data_policy_cid").unwrap()
      if contract_string(retention, "effective_data_policy_cid") != Some(policy) {
        let writer = @encode.construction_measuring_writer(
          max_bytes, max_nodes, max_depth,
        )
        active = Some(writer)
        emit_result_retention_for_data_policy(writer, retention, policy)
        bodies.push(
          (
            "result_retention_policy",
            @encode.finish_construction_measurement(writer),
          ),
        )
      }
      let writer = @encode.construction_measuring_writer(
        max_bytes, max_nodes, max_depth,
      )
      active = Some(writer)
      emit_acquisition_scope_body(writer, writer => {
        emit_acquisition_scope_entry(writer, producer, Some(producer), None)
      })
      bodies.push(
        ("acquisition_scope", @encode.finish_construction_measurement(writer)),
      )
      let writer = @encode.construction_measuring_writer(
        max_bytes, max_nodes, max_depth,
      )
      active = Some(writer)
      emit_occurrence_ordering_evidence_body(
        producer,
        source.identity,
        "source",
        writer,
      )
      bodies.push(
        ("ordering_evidence", @encode.finish_construction_measurement(writer)),
      )
      let writer = @encode.construction_measuring_writer(
        max_bytes, max_nodes, max_depth,
      )
      active = Some(writer)
      emit_acquisition_relation_body(
        writer,
        producer,
        evidence_string(input.value, "logical_relation_cid").unwrap(),
        evidence_string(input.value, "relation_schema_cid").unwrap(),
        producer,
        producer,
        retention.identity,
        policy,
        rows[index].to_int64(),
        "complete",
        "source",
        source.identity,
      )
      bodies.push(
        (
          "acquisition_relation",
          @encode.finish_construction_measurement(writer),
        ),
      )
    }
    if !include_union {
      return Ok(bodies)
    }
    let writer = @encode.construction_measuring_writer(
      max_bytes, max_nodes, max_depth,
    )
    active = Some(writer)
    emit_acquisition_scope_body(writer, writer => {
      for source in sources {
        let producer = evidence_string(source.value, "source_contract_cid").unwrap()
        emit_acquisition_scope_entry(writer, producer, Some(producer), None)
      }
    })
    bodies.push(
      ("acquisition_scope", @encode.finish_construction_measurement(writer)),
    )
    Ok(bodies)
  } catch {
    _ => {
      if active is Some(writer) {
        @encode.cancel_writer(writer)
      }
      Err(Encoding)
    }
  }
}
