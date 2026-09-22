///|
pub(all) enum NativeDuckDBIssue {
  UnsupportedTarget
  InvalidLimits
  LibraryLoad(String)
  DatabaseOpen(String)
  Query(String)
  CapacityExceeded
  Closed
} derive(Eq, Debug)

///|
/// Physical engine allocation selected before opening DuckDB. The enclosing
/// execution reservation also includes the Connector's separate scratch.
pub(all) struct NativeDuckDBOpenLimits {
  memory_bytes : Int64
  threads : Int
  external_access : Bool
  read_only : Bool
} derive(Eq, Debug)

///|
pub fn restricted_open_limits(memory_bytes : Int64) -> NativeDuckDBOpenLimits {
  { memory_bytes, threads: 1, external_access: false, read_only: false, }
}

///|
/// One bounded physical DuckDB batch. `columns_json` is connector-private
/// column-major transport, not canonical ActQL data or completion evidence.
pub(all) struct NativeDuckDBChunk {
  row_count : Int
  columns_json : String
} derive(Eq, Debug)

///|
/// One already admitted physical value for a prepared DuckDB parameter. This
/// is an adapter value, not a logical ActQL value or an admission shortcut.
pub(all) enum NativeDuckDBParameter {
  NullValue
  BooleanValue(Bool)
  DoubleValue(Double)
  TextValue(String)
  DecimalValue(String, Int, Int)
  DateValue(Int)
  TimestampValue(Int64)
} derive(Eq, Debug)
