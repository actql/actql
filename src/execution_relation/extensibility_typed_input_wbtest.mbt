///|
// Mutable caller buffers are copied to private typed storage after validation.
// This restricted physical inlet is not a supplied-input or producer proof API.
priv struct ExtNumberInput {
  values : Array[Double]
  valid : Array[Byte]
}

///|
priv enum ExtInputIssue {
  Shape
  UnsupportedColumn(Int)
  InvalidCell(Int, Int)
  Limit
} derive(Eq, Debug)

///|
// Account the retained inlet buffers separately from the sealed destination.
// These are nominal typed capacities, not allocator/RSS measurements.
fn ext_number_source(
  columns : Array[ExtNumberInput],
  ledger : LayoutLedger,
) -> Result[LayoutOwnedBuffer[Array[ExtNumberInput]], ExtInputIssue] {
  let mut bytes = 0
  for column in columns {
    if !spend_control(ledger.work, 1) {
      return Err(Limit)
    }
    if column.values.length() > (2147483647 - bytes) / 8 {
      return Err(Limit)
    }
    bytes += column.values.length() * 8
    if column.valid.length() > 2147483647 - bytes {
      return Err(Limit)
    }
    bytes += column.valid.length()
  }
  match
    allocate_owned_layout_buffer(ledger, columns.length(), bytes, fn() {
      columns
    }) {
    Ok(source) => Ok(source)
    Err(_) => Err(Limit)
  }
}

///|
fn ext_admit_owned_numbers(
  schema : @schema.Schema,
  names : Array[String],
  source : LayoutOwnedBuffer[Array[ExtNumberInput]],
  count : Int,
  max_rows : Int,
  ledger : LayoutLedger,
) -> Result[LayoutStorage, ExtInputIssue] {
  if source.lease.released ||
    !physical_equal(source.lease.buffer.ledger, ledger) {
    return Err(Shape)
  }
  guard source.value is Some(columns) else { return Err(Shape) }
  ext_admit_numbers(schema, names, columns, count, max_rows, ledger)
}

///|
fn ext_admit_numbers(
  schema : @schema.Schema,
  names : Array[String],
  columns : Array[ExtNumberInput],
  count : Int,
  max_rows : Int,
  ledger : LayoutLedger,
) -> Result[LayoutStorage, ExtInputIssue] {
  if count < 0 ||
    max_rows < 0 ||
    names.length() != columns.length() ||
    names.length() != @schema.field_count(schema) {
    return Err(Shape)
  }
  if count > max_rows || count > 238609294 {
    return Err(Limit)
  }
  // Scan caller buffers in logical row order, with no row object or Value
  // matrix. Canonical numeric/null admission is independent of storage copying.
  for column in 0..<columns.length() {
    if !spend_control(ledger.work, 1) ||
      !spend_control_text(ledger.work, names[column]) {
      return Err(Limit)
    }
    let field = @schema.field_at(schema, column).unwrap()
    if @schema.reference_name(field.name) != names[column] ||
      columns[column].values.length() != count ||
      columns[column].valid.length() != count {
      return Err(Shape)
    }
    if !(field.contract.shape is @contract.Number) {
      return Err(UnsupportedColumn(column))
    }
  }
  for row in 0..<count {
    if !spend_control(ledger.work, 1) {
      return Err(Limit)
    }
    for column in 0..<columns.length() {
      if !spend_control(ledger.work, 1) {
        return Err(Limit)
      }
      let validity = columns[column].valid[row]
      let field = @schema.field_at(schema, column).unwrap()
      if validity > 1 || (validity == 0 && !field.contract.nullable) {
        return Err(InvalidCell(row, column))
      }
      if validity == 1 {
        let n = columns[column].values[row]
        if n.is_nan() || n.is_inf() || (n == 0.0 && 1.0 / n < 0.0) {
          return Err(InvalidCell(row, column))
        }
      }
    }
  }
  let buffers : Array[LayoutOwnedBuffer[LayoutColumn]] = []
  for column in columns {
    // Allocation and copy work are reserved while caller storage still lives.
    if !spend_control(ledger.work, count) {
      for buffer in buffers {
        ignore(release_owned_layout_buffer(ledger, buffer))
      }
      return Err(Limit)
    }
    match
      allocate_owned_layout_buffer(ledger, 1, count * 9, fn() {
        LayoutColumn::Numeric(
          FixedArray::makei(count, i => {
            if column.valid[i] == 0 {
              0.0
            } else {
              column.values[i]
            }
          }),
          FixedArray::makei(count, i => column.valid[i]),
        )
      }) {
      Ok(buffer) => buffers.push(buffer)
      Err(_) => {
        for buffer in buffers {
          ignore(release_owned_layout_buffer(ledger, buffer))
        }
        return Err(Limit)
      }
    }
  }
  Ok({
    body: OwnedColumnArrays(buffers),
    count,
    width: columns.length(),
    selection: None,
    owned_selection: None,
  })
}

///|
test "typed inlet validates and seals caller buffers without a row matrix" {
  let owner = row_owner("")
  let schema = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap().schema
  let a : ExtNumberInput = { values: [1.0, 2.0], valid: [1, 1], }
  let b : ExtNumberInput = { values: [3.0, 4.0], valid: [1, 1], }
  let ledger = layout_ledger(2, 36, 100)
  let storage = ext_admit_numbers(schema, ["a", "b"], [a, b], 2, 2, ledger).unwrap()
  a.values[0] = 999
  a.valid[1] = 0
  b.values.clear()
  assert_true(layout_cell(storage, 0, 0) is Some(Number(1)))
  assert_true(layout_cell(storage, 1, 0) is Some(Number(2)))
  assert_true(layout_cell(storage, 1, 1) is Some(Number(4)))
  assert_eq((ledger.slots.live, ledger.bytes.live), (2, 36))
  release_layout_columns(storage)
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
}

///|
test "typed inlet rejects noncanonical cells and rolls back partial allocation" {
  let schema = capture_values(
      row_owner(""),
      0,
      max_rows=2,
      run_limits().input_values,
    ).unwrap().schema
  let good : ExtNumberInput = { values: [1.0, 2.0], valid: [1, 1], }
  for
    invalid in [
      ExtNumberInput::{ values: [-0.0, 2.0], valid: [1, 1], },
      ExtNumberInput::{ values: [1.0 / 0.0, 2.0], valid: [1, 1], },
      ExtNumberInput::{ values: [1.0, 2.0], valid: [2, 1], },
      ExtNumberInput::{ values: [1.0, 2.0], valid: [0, 1], },
    ] {
    let ledger = layout_ledger(2, 36, 100)
    assert_eq(
      ext_admit_numbers(schema, ["a", "b"], [good, invalid], 2, 2, ledger).map(_ => {
        ()
      }),
      Err(InvalidCell(0, 1)),
    )
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  }
  let short = layout_ledger(2, 35, 100)
  assert_eq(
    ext_admit_numbers(schema, ["a", "b"], [good, good], 2, 2, short).map(_ => ()),
    Err(Limit),
  )
  assert_eq((short.slots.live, short.bytes.live), (0, 0))
  assert_eq(short.bytes.peak, 18)
  let rows = layout_ledger(2, 36, 100)
  assert_eq(
    ext_admit_numbers(schema, ["a", "b"], [good, good], 2, 1, rows).map(_ => ()),
    Err(Limit),
  )
  assert_eq(rows.bytes.peak, 0)
}

///|
test "typed inlet source and destination coexist under the same physical limit" {
  let schema = capture_values(
      row_owner(""),
      0,
      max_rows=2,
      run_limits().input_values,
    ).unwrap().schema
  for cap in [71, 72] {
    let ledger = layout_ledger(4, cap, 1000)
    let columns = [
      ExtNumberInput::{ values: [1.0, 2.0], valid: [1, 1], },
      ExtNumberInput::{ values: [3.0, 4.0], valid: [1, 1], },
    ]
    let source = ext_number_source(columns, ledger).unwrap()
    let destination = ext_admit_owned_numbers(
      schema,
      ["a", "b"],
      source,
      2,
      2,
      ledger,
    )
    if cap == 71 {
      assert_true(destination is Err(Limit))
      assert_eq((ledger.slots.live, ledger.bytes.live), (2, 36))
      assert_true(source.value is Some(_))
    } else {
      let storage = destination.unwrap()
      assert_eq((ledger.slots.live, ledger.bytes.live), (4, 72))
      columns[0].values[0] = 999
      release_owned_layout_buffer(ledger, source).unwrap()
      assert_eq((ledger.slots.live, ledger.bytes.live), (2, 36))
      assert_true(layout_cell(storage, 0, 0) is Some(Number(1)))
      assert_true(
        ext_admit_owned_numbers(schema, ["a", "b"], source, 2, 2, ledger)
        is Err(Shape),
      )
      release_layout_columns(storage)
    }
    if !source.lease.released {
      release_owned_layout_buffer(ledger, source).unwrap()
    }
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  }
}
