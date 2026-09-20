///|
pub(all) enum NativeDuckDBIssue {
  UnsupportedTarget
  InvalidLimits
  LibraryLoad(String)
  DatabaseOpen(String)
  Query(String)
  CapacityExceeded
  Closed
}

///|
/// One bounded physical DuckDB batch. `columns_json` is connector-private
/// column-major transport, not canonical ActQL data or completion evidence.
pub(all) struct NativeDuckDBChunk {
  row_count : Int
  columns_json : String
} derive(Eq, Debug)
