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
