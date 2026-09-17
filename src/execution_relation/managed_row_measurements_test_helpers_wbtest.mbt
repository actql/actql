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
  if left.count != right.count {
    return false
  }
  for index in 0..<left.count {
    if managed_row_measurement_get(left, index) !=
      managed_row_measurement_get(right, index) {
      return false
    }
  }
  true
}
