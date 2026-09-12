///|
/// Package-private physical reads for row-index algorithms. Implementations
/// expose no mutable storage. Callers validate coordinates and charge work;
/// the layout does not determine comparison, ordering or key semantics.
priv trait IndexedRows {
  fn row_count(Self) -> Int
  fn column_count(Self) -> Int
  fn row_width(Self, Int) -> Int
  fn read_cell(Self, Int, Int) -> Value
}

///|
impl IndexedRows for Table with fn row_count(self) {
  self.rows.length()
}

///|
impl IndexedRows for Table with fn column_count(self) {
  self.names.length()
}

///|
impl IndexedRows for Table with fn row_width(self, row) {
  self.rows[row].length()
}

///|
impl IndexedRows for Table with fn read_cell(self, row, column) {
  self.rows[row][column]
}
