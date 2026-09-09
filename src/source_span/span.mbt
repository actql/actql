///|
/// Original source coordinates: zero-based, end-exclusive UTF-8 byte offsets;
/// one-based lines and Unicode scalar columns. CRLF is one newline; tabs are one
/// column. A leading BOM consumes bytes but does not advance the first column.
pub(all) struct Span {
  start_byte : Int
  end_byte : Int
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
  source_path : String
} derive(Eq, Debug)
