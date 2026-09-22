///|
// Generated from adapters/connectors/duckdb/environment-contract.json.
fn canonical_environment_readback() -> Array[(String, String)] {
  [
    ("allow_unsigned_extensions", "false"),
    ("autoinstall_known_extensions", "false"),
    ("autoload_known_extensions", "false"),
    ("default_collation", "binary"),
    ("max_temp_directory_size", "0 bytes"),
    ("preserve_insertion_order", "true"),
  ]
}
