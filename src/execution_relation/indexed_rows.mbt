///|
/// Package-private physical reads for row-index algorithms. Implementations
/// expose no mutable storage. Callers validate coordinates and charge work;
/// the layout does not determine comparison, ordering or key semantics.
priv trait IndexedRows {
  fn row_count(Self) -> Int
  fn column_count(Self) -> Int
  fn row_width(Self, Int) -> Int
  fn read_cell(Self, Int, Int) -> Value
  fn cell_present(Self, Int, Int) -> Bool = _
}

///|
impl IndexedRows with fn cell_present(_self, _row, _column) {
  true
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

///|
/// Checked metadata stays outside the physical buffers. This trait is private;
/// implementing a storage reader is not evidence of whole-Program admission.
priv trait RelationRows: IndexedRows {
  fn checked_owner(Self) -> @lower.BoundPrepared
  fn relation_id(Self) -> String
  fn field_names(Self) -> Array[String]
}

///|
impl RelationRows for Table with fn checked_owner(self) {
  self.owner
}

///|
impl RelationRows for Table with fn relation_id(self) {
  self.id
}

///|
impl RelationRows for Table with fn field_names(self) {
  self.names
}

///|
priv trait RowValues {
  fn value_count(Self) -> Int
  fn value_at(Self, Int) -> Value
  fn value_present(Self, Int) -> Bool = _
}

///|
impl RowValues with fn value_present(_self, _column) {
  true
}

///|
impl RowValues for Array[Value] with fn value_count(self) {
  self.length()
}

///|
impl RowValues for Array[Value] with fn value_at(self, column) {
  self[column]
}

///|
/// A bounded coordinate, not a reconstructed row object or copied array.
priv struct IndexedRow[T] {
  table : T
  row : Int
}

///|
impl[T : IndexedRows] RowValues for IndexedRow[T] with fn value_count(self) {
  self.table.row_width(self.row)
}

///|
impl[T : IndexedRows] RowValues for IndexedRow[T] with fn value_at(self, column) {
  self.table.read_cell(self.row, column)
}

///|
impl[T : IndexedRows] RowValues for IndexedRow[T] with fn value_present(
  self,
  column,
) {
  self.table.cell_present(self.row, column)
}
