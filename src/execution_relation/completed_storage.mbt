///|
/// Private storage only: no expression state, continuation or success evidence.
/// Numeric buffers are sealed by their builder before reaching completion.
priv struct CompletedNumberColumn {
  values : FixedArray[Double]
  valid : FixedArray[Byte]
}

///|
priv struct CompletedNumbers {
  owner : @lower.BoundPrepared
  id : String
  names : Array[String]
  columns : Array[CompletedNumberColumn]
  count : Int
  // Composed physical row coordinates, not a chain of mutable views.
  selection : Array[Int]?
}

///|
priv struct CompletedAdmitted {
  owner : @lower.BoundPrepared
  id : String
  names : Array[String]
  rows : Array[Array[@admitted.Value]]
}

///|
// Sealed column storage for mixed scalar and admitted value domains. The
// columns are invocation-local while building and are never exposed mutably
// after completion.
priv struct CompletedColumns {
  owner : @lower.BoundPrepared
  id : String
  names : Array[String]
  columns : Array[Array[Value]]
  count : Int
  // Composed physical row coordinates, not a chain of mutable views.
  selection : Array[Int]?
}

///|
priv enum CompletedTable {
  RowTable(Table)
  NumberTable(CompletedNumbers)
  AdmittedTable(CompletedAdmitted)
  ColumnTable(CompletedColumns)
}

///|
impl IndexedRows for CompletedTable with fn row_count(self) {
  match self {
    RowTable(table) => table.rows.length()
    NumberTable(table) => table.count
    AdmittedTable(table) => table.rows.length()
    ColumnTable(table) => table.count
  }
}

///|
impl IndexedRows for CompletedTable with fn column_count(self) {
  match self {
    RowTable(table) => table.names.length()
    NumberTable(table) => table.names.length()
    AdmittedTable(table) => table.names.length()
    ColumnTable(table) => table.names.length()
  }
}

///|
impl IndexedRows for CompletedTable with fn row_width(self, row) {
  match self {
    RowTable(table) => table.rows[row].length()
    NumberTable(table) => table.names.length()
    AdmittedTable(table) => table.names.length()
    ColumnTable(table) => table.names.length()
  }
}

///|
impl IndexedRows for CompletedTable with fn read_cell(self, row, column) {
  match self {
    RowTable(table) => table.rows[row][column]
    AdmittedTable(table) => capture(table.rows[row][column])
    ColumnTable(table) => {
      let index = match table.selection {
        Some(indices) => indices[row]
        None => row
      }
      table.columns[column][index]
    }
    NumberTable(table) => {
      let index = match table.selection {
        Some(indices) => indices[row]
        None => row
      }
      let buffer = table.columns[column]
      if buffer.valid[index] == b'\x00' {
        Null
      } else {
        Number(buffer.values[index])
      }
    }
  }
}

///|
impl RelationRows for CompletedTable with fn checked_owner(self) {
  match self {
    RowTable(table) => table.owner
    NumberTable(table) => table.owner
    AdmittedTable(table) => table.owner
    ColumnTable(table) => table.owner
  }
}

///|
impl RelationRows for CompletedTable with fn relation_id(self) {
  match self {
    RowTable(table) => table.id
    NumberTable(table) => table.id
    AdmittedTable(table) => table.id
    ColumnTable(table) => table.id
  }
}

///|
impl RelationRows for CompletedTable with fn field_names(self) {
  match self {
    RowTable(table) => table.names
    NumberTable(table) => table.names
    AdmittedTable(table) => table.names
    ColumnTable(table) => table.names
  }
}

///|
priv enum CompletedStore {
  RowStore(TableStore[Table])
  PhysicalStore(TableStore[CompletedTable])
  ImportedStore(Int, @pipeline.Target, CompletedTable)
  RetainedStore(Int, @pipeline.Target, RetainedOutputMaterial)
}

///|
fn CompletedStore::input_count(self : CompletedStore) -> Int {
  match self {
    RowStore(store) => store.wiring.input_count
    PhysicalStore(store) => store.wiring.input_count
    ImportedStore(count, _, _) | RetainedStore(count, _, _) => count
  }
}

///|
fn CompletedStore::table_at(
  self : CompletedStore,
  slot : Int,
) -> CompletedTable? {
  match self {
    RowStore(store) => store.tables[slot].map(held => RowTable(held.table))
    PhysicalStore(store) => store.tables[slot].map(held => held.table)
    ImportedStore(count, target, table) =>
      match target {
        Step(index) => if slot == count + index { Some(table) } else { None }
        Input(_) => None
      }
    RetainedStore(_, _, _) => None
  }
}

///|
// Conservative physical capacity in addition to the common logical-shaped
// table reservation. A short selection retains its entire backing buffers.
// Sharing across handles does not silently discount this receiver's ceiling.
fn reserve_completed_storage(
  table : CompletedTable,
  workspace : RowWorkspace,
  control : ControlBudget,
) -> Bool {
  match table {
    RowTable(_) | AdmittedTable(_) => true
    ColumnTable(table) => {
      if !reserve_slots(workspace, table.columns.length()) {
        return false
      }
      for column in table.columns {
        if !spend_control(control, 1) ||
          !reserve_slots(workspace, column.length()) {
          return false
        }
      }
      match table.selection {
        None => true
        Some(indices) => reserve_slots(workspace, indices.length())
      }
    }
    NumberTable(table) => {
      if !reserve_slots(workspace, table.columns.length()) {
        return false
      }
      for column in table.columns {
        if !spend_control(control, 1) ||
          !reserve_slots(workspace, column.values.length()) ||
          !reserve_slots(workspace, column.valid.length()) {
          return false
        }
      }
      match table.selection {
        None => true
        Some(indices) => reserve_slots(workspace, indices.length())
      }
    }
  }
}
