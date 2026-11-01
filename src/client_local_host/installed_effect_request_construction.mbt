///|
/// The selected standard Effect constructor consumes the SAME native provider
/// capacity and the existing byte-JSON parser/index/key-admission inventory.
/// This is constructor DATA only: Host request/response/secret/failed-child and
/// saved-body controls must still be added to a complete implementation extent.
/// No Source acquisition/capacity/permission is reused or issued here.
pub fn installed_json_effect_request_construction_capacity(
  provider : @execution.ExecutionCapacity,
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  if max_input_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return None
  }
  guard installed_source_response_preserving_workspace(
      max_input_bytes, max_nodes, max_depth,
    )
    is Some(decoded) else {
    return None
  }
  // Same parse_json_bytes_preserving/decode.admit family as the reader's
  // private constructor inventory, NOT its normalizing alternative or its
  // transport/Run allowance. Data-key Preview admission preserves original
  // text; Native/configuration normalization belongs to its own provider.
  // Keep the whole decoding envelope beside retained native values so String
  // backing is never assumed severed merely because the decoder returned.
  // The mapper additionally owns its input JSON String and encoded Bytes.
  guard @execution.compose_preparation_representation([
      decoded,
      {
        record_headers: 2L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: max_input_bytes.to_int64(),
        owned_wire_bytes: max_input_bytes.to_int64(),
      },
    ])
    is Some(retained) &&
    @execution.preparation_execution_capacity({
      retained,
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(json) else {
    return None
  }
  @execution.add_execution_capacity(provider, json)
}

///|
/// SAME byte parser/index/key-normalization construction over an already
/// received response. The original received Bytes remain with the physical
/// child; this does not encode another input String/Bytes or fund transport,
/// credentials, JS projection, saved response custody or their overlap.
pub fn installed_json_effect_response_construction_capacity(
  provider : @execution.ExecutionCapacity,
  max_response_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  if max_response_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return None
  }
  guard installed_source_response_workspace(
      max_response_bytes, max_nodes, max_depth,
    )
    is Some(decoded) &&
    @canonical.nfc_lf_construction_scratch_extent(max_response_bytes)
    is Some(scratch) &&
    decoded.record_headers >= scratch.record_headers &&
    decoded.reference_slots >= scratch.reference_slots &&
    decoded.scalar_words >= scratch.scalar_words &&
    decoded.owned_utf16_units >= scratch.owned_utf16_units &&
    @execution.preparation_execution_capacity({
      // Keep every original Source/index/key/output backing. The Unicode
      // Owner alone identifies the scalar arrays and intermediate text that
      // cannot escape its synchronous normalization. Failed construction
      // still retains this SAME complete execution peak until cleanup.
      retained: {
        record_headers: decoded.record_headers - scratch.record_headers,
        reference_slots: decoded.reference_slots - scratch.reference_slots,
        scalar_words: decoded.scalar_words - scratch.scalar_words,
        owned_utf16_units: decoded.owned_utf16_units - scratch.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: scratch.record_headers,
        reference_slots: scratch.reference_slots,
        scalar_words: scratch.scalar_words,
        owned_utf16_units: scratch.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(json) else {
    return None
  }
  @execution.add_execution_capacity(provider, json)
}

///|
/// Compose the SAME native JSON export with its actual Host JSON.parse
/// constructor. Optional byte-JSON input uses the existing indexed decoder
/// inventory; a present output uses literal JSON geometry and borrows the
/// already-owned native String. An absent output is the actual no-native-JSON
/// request phase, not a fabricated empty JSON document or spare allowance.
/// No request/response/secret/transport/failed-child allowance
/// or permission can be inferred from this constructor-only result.
pub fn installed_standard_create_constructor_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  guard original is Some(entries) &&
    (entries.length() == 2 || entries.length() == 4) else {
    return Err(Unsupported)
  }
  let capacities = []
  for (native, input, output) in entries {
    let combined = match output {
      None => native
      Some(output) => {
        guard @source.json_literal_construction_extent(
            output.max_input_bytes,
            output.max_nodes,
            output.max_depth,
          )
          is Some(parsed) &&
          @execution.preparation_execution_capacity({
            retained: {
              record_headers: parsed.record_headers,
              reference_slots: parsed.reference_slots,
              scalar_words: parsed.scalar_words,
              owned_utf16_units: parsed.owned_utf16_units,
              owned_wire_bytes: 0L,
            },
            workspace: {
              record_headers: 0L,
              reference_slots: 0L,
              scalar_words: 0L,
              owned_utf16_units: 0L,
              owned_wire_bytes: 0L,
            },
            retained_nodes: 0L,
            workspace_nodes: 0L,
            retained_bytes: 0L,
            workspace_bytes: 0L,
          })
          is Some(host) &&
          @execution.add_execution_capacity(native, host) is Some(combined) else {
          return Err(Unsupported)
        }
        combined
      }
    }
    let capacity = match input {
      None => combined
      Some(limits) =>
        match
          installed_json_effect_response_construction_capacity(
            combined,
            limits.max_input_bytes,
            limits.max_nodes,
            limits.max_depth,
          ) {
          Some(value) => value
          None => return Err(Unsupported)
        }
    }
    capacities.push(capacity)
  }
  Ok(capacities)
}
