///|
/// Measure the registered identity identity_writer with the same canonical encoder.
/// Every body here is a nonempty object: union with this singleton adds its
/// encoded size minus one (two outer braces removed, one comma inserted).
fn measured_complete_publication_bytes(
  kind : String,
  writer : @encode.Writer,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int {
  try {
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(writer)
    guard contract_spec(kind) is Some(spec) else { return max_wire_bytes }
    let identity_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    @encode.begin_object(identity_writer)
    @encode.key(identity_writer, spec.identity)
    @encode.string_value(
      identity_writer, "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    )
    @encode.end_object(identity_writer)
    let (member_bytes, _, _) = @encode.finish_measurement_usage(identity_writer)
    let added = member_bytes - 1
    if nodes >= max_nodes || depth > max_depth || bytes > max_wire_bytes - added {
      max_wire_bytes
    } else {
      bytes + added
    }
  } catch {
    _ => max_wire_bytes
  }
}

///|
/// Ordinary publication's state frontier, not a generic record-history bound.
/// Each named obligation is separately durable: current preparing, committing,
/// unknown and terminal, plus a possible foreign winner's missing terminal.
/// A resolved foreign index can require both that winner's success and this
/// attempt's cancellation; the winner is not assumed funded by this attempt.
/// Values are index/current preparing/committing/unknown/terminal/winner terminal.
/// No contract, timestamp assertion, or authority is issued by this projection.
pub fn ordinary_publication_frontier_byte_bounds(
  request : PublicationContract,
  result_count : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Array[Int] {
  if request.name != "publication_request" ||
    result_count < 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return []
  }
  guard contract_string(request, "namespace_id") is Some(namespace_id) &&
    contract_string(request, "authority_scope_cid") is Some(authority) else {
    return []
  }
  guard @json.object_field(request.value, "inventory")
    is Some(@json.Array(inventory)) &&
    @json.array_count(inventory) == result_count else {
    return []
  }
  let cid = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  // valid_timestamp admits exactly 24 ASCII characters. Future invalid clocks
  // fail issuance; measuring an accepted width does not sample the caller clock.
  let timestamp = "2000-01-01T00:00:00.000Z"
  let result : Array[Int] = []
  for position in 0..<6 {
    let bound = (fn() -> Int {
      try {
        let writer = @encode.measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
        if position == 0 {
          emit_public_index_entry_body(
            namespace_id,
            authority,
            cid,
            cid,
            cid,
            cid,
            cid,
            cid,
            cid,
            timestamp,
            result_count,
            _ => cid,
            writer,
          )
          measured_complete_publication_bytes(
            "public_index_entry", writer, max_wire_bytes, max_nodes, max_depth,
          )
        } else {
          let state = match position {
            1 => "preparing"
            2 => "committing"
            3 => "publication_unknown"
            _ => "succeeded"
          }
          // A preexisting admitted predecessor can have any accepted safe
          // count. Keep its full decimal width even on the first frontier edge.
          emit_publication_record_body(
            cid,
            Some(cid),
            state,
            timestamp,
            if position >= 4 {
              Some(cid)
            } else {
              None
            },
            None,
            [],
            9007199254740991L,
            writer,
          )
          measured_complete_publication_bytes(
            "publication_record", writer, max_wire_bytes, max_nodes, max_depth,
          )
        }
      } catch {
        _ => max_wire_bytes
      }
    })()
    result.push(bound)
  }
  result
}

///|
/// Manifest skeleton and complete artifact bounds use their actual issuers'
/// emitters. Null is a measurement placeholder only, never a sealed artifact.
/// Each embedded artifact replaces its four-byte null; no CID-only shortcut.
pub fn ordinary_publication_manifest_byte_bound(
  request : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int {
  if request.name != "publication_request" ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return max_wire_bytes
  }
  guard @json.object_field(request.value, "inventory")
    is Some(@json.Array(inventory)) else {
    return max_wire_bytes
  }
  let count = @json.array_count(inventory)
  let cid = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  try {
    let artifact_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_complete_result_artifact_body(
      cid, cid, cid, cid, cid, 2147483647, cid, cid, cid, artifact_writer,
    )
    let artifact_bytes = measured_complete_publication_bytes(
      "result_artifact", artifact_writer, max_wire_bytes, max_nodes, max_depth,
    )
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_result_manifest_fields(
      cid,
      cid,
      count,
      index => {
        contract_string_from_value(
          @json.array_at(inventory, index).unwrap(),
          "result_name",
        ).unwrap()
      },
      _ => None,
      writer,
    )
    let skeleton = measured_complete_publication_bytes(
      "result_manifest", writer, max_wire_bytes, max_nodes, max_depth,
    )
    let additional = artifact_bytes - 4
    if artifact_bytes <= 4 || count > (max_wire_bytes - skeleton) / additional {
      max_wire_bytes
    } else {
      skeleton + count * additional
    }
  } catch {
    _ => max_wire_bytes
  }
}

///|
/// All known receipt inputs remain their original nominal Common values. Only
/// future artifact/manifest bodies and distinct derivation identities are
/// bounded; unknown nested bodies are never replaced by CID-only estimates.
pub fn ordinary_publication_receipt_byte_bound(
  admission : RunPublicationAdmission,
  request : PublicationContract,
  invocation : PublicationContract,
  observation : RunEvidenceValue,
  normalization : RunEvidenceValue,
  binding_names : Array[String],
  binding_digests : Array[String],
  sources : Array[RunEvidenceValue],
  models : Array[RunEvidenceValue],
  barrier_cids : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int {
  if request.name != "publication_request" ||
    invocation.name != "run_invocation" ||
    observation.name != "observation_set" ||
    normalization.name != "normalization_journal" ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return max_wire_bytes
  }
  guard @json.object_field(request.value, "inventory")
    is Some(@json.Array(inventory)) &&
    contract_string(admission.compiled_plan, "compiler_version")
    is Some(compiler_version) &&
    contract_string(admission.compiled_plan, "aoa_ir_version")
    is Some(aoa_ir_version) &&
    contract_string(admission.compiled_plan, "program_semantics_cid")
    is Some(program_semantics_cid) &&
    contract_string(admission.compiled_plan, "aoa_logical_cid")
    is Some(aoa_logical_cid) &&
    contract_string_from_value(
      admission.template.value,
      "program_definition_cid",
    )
    is Some(program_definition_cid) &&
    contract_string_from_value(
      admission.template.value,
      "check_environment_cid",
    )
    is Some(check_environment_cid) &&
    contract_string_from_value(observation.value, "consistency")
    is Some(consistency) &&
    receipt_bindings(binding_names, binding_digests) is Ok(bindings) &&
    receipt_source_identities(sources) is Ok(source_cids) &&
    receipt_model_identities(models) is Ok(model_cids) &&
    receipt_sorted_cids(barrier_cids, "barrier_attempt_receipt_cids")
    is Ok(barriers) else {
    return max_wire_bytes
  }
  let count = @json.array_count(inventory)
  let cid = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  try {
    let artifact_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_complete_result_artifact_body(
      cid, cid, cid, cid, cid, 2147483647, cid, cid, cid, artifact_writer,
    )
    let artifact_bytes = measured_complete_publication_bytes(
      "result_artifact", artifact_writer, max_wire_bytes, max_nodes, max_depth,
    )
    let map_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_result_artifact_inventory(
      count,
      index => {
        contract_string_from_value(
          @json.array_at(inventory, index).unwrap(),
          "result_name",
        ).unwrap()
      },
      _ => None,
      map_writer,
    )
    let (map_bytes, _, _) = @encode.finish_measurement_usage(map_writer)
    if artifact_bytes <= 4 ||
      count > (max_wire_bytes - map_bytes) / (artifact_bytes - 4) {
      return max_wire_bytes
    }
    let artifacts = map_bytes + count * (artifact_bytes - 4)
    let manifest = ordinary_publication_manifest_byte_bound(
      request, max_wire_bytes, max_nodes, max_depth,
    )
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_effect_free_run_receipt_body(
      aoa_ir_version,
      aoa_logical_cid,
      count,
      _ => cid,
      barriers,
      bindings,
      check_environment_cid,
      admission.compiled_plan_cid,
      compiler_version,
      consistency,
      [],
      model_cids,
      source_cids,
      invocation.identity,
      normalization.identity,
      observation.value,
      observation.identity,
      admission.prepared.value,
      program_definition_cid,
      program_semantics_cid,
      None,
      None,
      cid,
      admission.authorization.value,
      sources,
      writer,
    )
    let skeleton = measured_complete_publication_bytes(
      "run_receipt", writer, max_wire_bytes, max_nodes, max_depth,
    )
    // The two null slots contribute eight bytes in the shared skeleton.
    if skeleton < 8 ||
      artifacts > max_wire_bytes - (skeleton - 8) ||
      manifest > max_wire_bytes - (skeleton - 8) - artifacts {
      max_wire_bytes
    } else {
      skeleton - 8 + artifacts + manifest
    }
  } catch {
    _ => max_wire_bytes
  }
}
