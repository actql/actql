///|
// This metadata projection retains original Source nodes and spans. Compute
// bodies are not Policy inputs and do not pass through the 8-KiB Policy reader.
// The complete original still passes the unchanged 64-KiB Source intake.
fn local_policy_source_fields(
  node : @source.Node,
  keys : Array[String],
) -> Array[@source.Field]? {
  guard node.value is @source.Object(fields) else { return None }
  if !fields.all(field => keys.contains(field.key)) {
    return None
  }
  Some(fields)
}

///|
fn local_policy_source_field(
  fields : Array[@source.Field],
  key : String,
) -> @source.Field? {
  fields.iter().find_first(field => field.key == key)
}

///|
/// A readonly view of the actual Run original's Policy inputs. It preserves
/// all remaining metadata/values and spans without serializing, normalizing,
/// evaluating or changing the original body or its identity. The omitted
/// registry/Values/fragment/ordered bodies remain separate original inputs to
/// their existing admission owners. This view issues no adoption or authority.
pub fn client_local_run_policy_metadata_cursor(
  original : Bytes,
) -> Result[@decode.Cursor, ClientLocalProductConfigurationIssue] {
  let root = match
    @source.parse_json_bytes_preserving(original, {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return Err(ConfigurationLimit)
  }
  guard local_policy_source_fields(root, ["native", "version"]) is Some(fields) &&
    local_policy_source_field(fields, "native") is Some(native_field) &&
    local_policy_source_fields(native_field.value, ["run"])
    is Some(native_fields) &&
    local_policy_source_field(native_fields, "run") is Some(run_field) &&
    local_policy_source_fields(run_field.value, [
      "namespace_id", "store_name", "store_authority_cid", "store_capacity_bytes",
      "store_objects", "store_record_bytes", "result_payload_bytes", "retention_policy_wire",
      "source_free",
    ])
    is Some(run_fields) &&
    local_policy_source_field(run_fields, "source_free") is Some(values_field) &&
    local_policy_source_fields(values_field.value, [
      "registry", "values", "fragment", "ordered", "result_policy_cid", "result_policy_wire",
    ])
    is Some(values_fields) else {
    return Err(UnsupportedAsset)
  }
  // All metadata fields retain their own original spans and decoded values.
  let values : @source.Node = {
    ..values_field.value,
    value: @source.Object(
      values_fields.filter(field => {
        field.key == "result_policy_cid" || field.key == "result_policy_wire"
      }),
    ),
  }
  let run : @source.Node = {
    ..run_field.value,
    value: @source.Object(
      run_fields.map(field => {
        if field.key == "source_free" {
          { ..field, value: values, }
        } else {
          field
        }
      }),
    ),
  }
  let native : @source.Node = {
    ..native_field.value,
    value: @source.Object(native_fields.map(field => { ..field, value: run, })),
  }
  let view : @source.Node = {
    ..root,
    value: @source.Object(
      fields.map(field => {
        if field.key == "native" {
          { ..field, value: native, }
        } else {
          field
        }
      }),
    ),
  }
  @decode.admit(view, {
    max_nodes: 8192,
    max_depth: 64,
    max_string_bytes: 8192,
    max_total_string_bytes: 65536,
  }).map_err(_ => ConfigurationLimit)
}
