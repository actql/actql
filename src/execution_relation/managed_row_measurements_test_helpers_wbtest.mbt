///|
fn managed_row_measurements_from_cells(
  cells : Array[(Int, Int, Bool)],
) -> ManagedRowMeasurements? {
  guard new_managed_row_measurements(cells.length()) is Some(index) else {
    return None
  }
  for cell in cells {
    if !managed_row_measurement_push(index, cell) {
      return None
    }
  }
  Some(index)
}

///|
fn managed_row_measurements_equal(
  left : ManagedRowMeasurements,
  right : ManagedRowMeasurements,
) -> Bool {
  left.count == right.count &&
  left.cells[0:left.count] == right.cells[0:right.count]
}
