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
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "sources")
    @encode.begin_array(writer)
    for key in keys {
      @json.emit_value(entries[key], writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-acquisition-scope/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  seal_publication_contract(
    "acquisition_scope", body, max_bytes, max_nodes, max_depth,
  ).map_err(issue => AcquisitionRelationIssue::Contract(issue))
}
