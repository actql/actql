///|
// The existing measurement ledger reads a single checked presence row without
// filling missing values or allocating a second dense representation.
priv struct SinglePresenceGuardRow {
  value : AdmittedRelationRow
}

///|
impl IndexedRows for SinglePresenceGuardRow with fn row_count(_self) {
  1
}

///|
impl IndexedRows for SinglePresenceGuardRow with fn column_count(self) {
  self.value.cells.length()
}

///|
impl IndexedRows for SinglePresenceGuardRow with fn row_width(self, _row) {
  self.value.cells.length()
}

///|
impl IndexedRows for SinglePresenceGuardRow with fn cell_present(
  self,
  _row,
  column,
) {
  self.value.cells[column] is Some(_)
}

///|
impl IndexedRows for SinglePresenceGuardRow with fn read_cell(
  self,
  _row,
  column,
) {
  capture(self.value.cells[column].unwrap())
}
