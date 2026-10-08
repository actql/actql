///|
/// Bounded content reference to a Connector-validated physical mapping. The
/// shared Owner does not interpret field IDs, file formats or backend types.
/// This content admission is not a Connector capability, approval, custody or
/// proof of physical validation. The selected Connector must admit its own
/// mapping before passing this reference into input binding or recovery.
struct StorageMappingReference {
  kind : @carrier.Kind
  cid : String
  schema_cid : String
  wire : String
}

///|
pub fn admit_storage_mapping_reference(
  kind : @carrier.Kind,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[StorageMappingReference, TableContractIssue] {
  let (value, cid) = match
    table_sealed_value(
      wire,
      "mapping_cid",
      max_bytes,
      max_nodes,
      max_depth,
      max_allowed_nodes=16384,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard ledger_cid(value, "schema_cid") is Some(schema_cid) &&
    ledger_string(value, "version") is Some(version) &&
    !version.is_empty() &&
    version.length() <= 256 else {
    return Err(InvalidShape)
  }
  Ok({ kind, cid, schema_cid, wire, })
}

///|
pub fn storage_mapping_reference_kind(
  value : StorageMappingReference,
) -> @carrier.Kind {
  value.kind
}

///|
pub fn storage_mapping_reference_cid(value : StorageMappingReference) -> String {
  value.cid
}

///|
pub fn storage_mapping_reference_schema_cid(
  value : StorageMappingReference,
) -> String {
  value.schema_cid
}

///|
/// Exact saved material remains available to the selected Connector for its
/// validation and recovery. A shared Owner must not infer a physical contract
/// from this opaque body or choose a different installation to interpret it.
pub fn storage_mapping_reference_json(
  value : StorageMappingReference,
) -> String {
  value.wire
}
