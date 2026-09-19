///|
/// DuckDB's Node adapter uses the same portable manifest admission as the
/// standard Host bridge. Only object snapshotting and Store I/O remain in JS.
#export_name("physicalManifestAdmit")
pub fn physical_manifest_admit(
  version : String,
  schema_contract_cid : String,
  view_contract_cid : String,
  codec_contract_cid : String,
  row_count : Int,
  chunk_cids : Array[String],
  chunk_byte_lengths : Array[Int64],
  chunk_row_counts : Array[Int],
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Array[String] {
  match
    @manifest.admit(
      version, schema_contract_cid, view_contract_cid, codec_contract_cid, row_count,
      chunk_cids, chunk_byte_lengths, chunk_row_counts, max_chunks, max_manifest_bytes,
      max_referenced_bytes,
    ) {
    Ok(value) => ["ok", ..@manifest.projection(value)]
    Err(InvalidManifest) => ["error", "invalid"]
    Err(ManifestLimit) => ["error", "limit"]
    Err(CountOverflow) => ["error", "overflow"]
    Err(RowCountMismatch) => ["error", "row-count"]
  }
}

///|
#export_name("physicalRepresentationContracts")
pub fn physical_representation_contracts(
  fields_frame : String,
  storage_order : Array[Int],
  max_contract_bytes : Int,
) -> Array[String] {
  match
    @manifest.admit_contracts(fields_frame, storage_order, max_contract_bytes) {
    Ok(value) => ["ok", ..@manifest.contract_projection(value)]
    Err(InvalidManifest) => ["error", "invalid"]
    Err(ManifestLimit) => ["error", "limit"]
    Err(CountOverflow) => ["error", "overflow"]
    Err(RowCountMismatch) => ["error", "row-count"]
  }
}
