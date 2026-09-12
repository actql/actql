///|
// Experimental physical storage only. No product dispatch or semantic opcode.
// All mutable buffers are sealed before a LayoutStorage is returned.
priv enum LayoutCandidate {
  RowLayout
  ValueColumns
  TypedColumns
} derive(Eq)

///|
priv enum LayoutColumn {
  Generic(FixedArray[Value])
  Numeric(FixedArray[Double], FixedArray[Byte])
  Flags(FixedArray[Byte], FixedArray[Byte])
}

///|
priv enum LayoutStorageBody {
  RowArrays(Array[Array[Value]])
  ColumnArrays(Array[LayoutColumn])
  OwnedColumnArrays(Array[LayoutOwnedBuffer[LayoutColumn]])
}

///|
priv struct LayoutStorage {
  body : LayoutStorageBody
  width : Int
  count : Int
  // Already composed against physical buffers, never a chain of prior views.
  selection : Array[Int]?
  owned_selection : LayoutOwnedBuffer[Array[Int]]?
}

///|
impl IndexedRows for LayoutStorage with fn row_count(self) {
  self.count
}

///|
impl IndexedRows for LayoutStorage with fn column_count(self) {
  self.width
}

///|
impl IndexedRows for LayoutStorage with fn row_width(self, _row) {
  self.width
}

///|
impl IndexedRows for LayoutStorage with fn read_cell(self, row, column) {
  layout_cell(self, row, column).unwrap()
}

///|
priv struct LayoutAllocation {
  ledger : LayoutLedger?
  slots : RowWorkspace
  // Nominal typed element bytes only, not allocator headers or process RSS.
  // In JS numeric storage is an ordinary numeric array, not Float64Array.
  bytes : RowWorkspace
  work : ControlBudget
}

///|
priv enum LayoutStorageIssue {
  Limit
  Shape
}

///|
fn layout_bytes(b : LayoutAllocation, count : Int, unit : Int) -> Bool {
  if count < 0 || unit < 1 || count > (b.bytes.limit - b.bytes.live) / unit {
    return false
  }
  reserve_slots(b.bytes, count * unit)
}

///|
fn import_layout(
  input : CapturedRows,
  candidate : LayoutCandidate,
  b : LayoutAllocation,
) -> Result[LayoutStorage, LayoutStorageIssue] {
  let count = input.rows.length()
  let width = @schema.field_count(input.schema)
  // Count source capture containers while destination allocation coexists.
  // Nested payload/Value object bytes are deliberately not invented here.
  if !reserve_slots(b.slots, count) || !reserve_slots(b.slots, width) {
    return Err(Limit)
  }
  for row in input.rows {
    if row.length() != width {
      return Err(Shape)
    }
    if !reserve_slots(b.slots, width) ||
      !spend_control(b.work, 1) ||
      !spend_control(b.work, width) {
      return Err(Limit)
    }
  }
  if candidate == RowLayout {
    if !reserve_slots(b.slots, count) {
      return Err(Limit)
    }
    for _i = 0; _i < count; _i = _i + 1 {
      if !reserve_slots(b.slots, width) ||
        !spend_control(b.work, 1) ||
        !spend_control(b.work, width) {
        return Err(Limit)
      }
    }
    return Ok({
      body: RowArrays(input.rows.map(row => row.map(capture))),
      width,
      count,
      selection: None,
      owned_selection: None,
    })
  }
  if !reserve_slots(b.slots, width) || !spend_control(b.work, width) {
    return Err(Limit)
  }
  // Reserve every destination before allocating any large column buffer.
  for column = 0; column < width; column = column + 1 {
    let contract = @schema.field_at(input.schema, column).unwrap().contract
    if !spend_control(b.work, count) {
      return Err(Limit)
    }
    if candidate == TypedColumns && contract.shape is @contract.Number {
      if !layout_bytes(b, count, 8) || !layout_bytes(b, count, 1) {
        return Err(Limit)
      }
    } else if candidate == TypedColumns && contract.shape is @contract.Boolean {
      if !layout_bytes(b, count, 1) || !layout_bytes(b, count, 1) {
        return Err(Limit)
      }
    } else if !reserve_slots(b.slots, count) {
      return Err(Limit)
    }
  }
  let columns : Array[LayoutColumn] = []
  for column = 0; column < width; column = column + 1 {
    let contract = @schema.field_at(input.schema, column).unwrap().contract
    if candidate == TypedColumns && contract.shape is @contract.Number {
      let values = FixedArray::make(count, 0.0)
      let valid : FixedArray[Byte] = FixedArray::make(count, 0)
      for row = 0; row < count; row = row + 1 {
        match capture(input.rows[row][column]) {
          Number(n) => {
            values[row] = n
            valid[row] = 1
          }
          Null => ()
          Boolean(_) | Text(_) | Captured(_) => return Err(Shape)
        }
      }
      columns.push(Numeric(values, valid))
    } else if candidate == TypedColumns && contract.shape is @contract.Boolean {
      let values : FixedArray[Byte] = FixedArray::make(count, 0)
      let valid : FixedArray[Byte] = FixedArray::make(count, 0)
      for row = 0; row < count; row = row + 1 {
        match capture(input.rows[row][column]) {
          Boolean(v) => {
            values[row] = if v { 1 } else { 0 }
            valid[row] = 1
          }
          Null => ()
          Number(_) | Text(_) | Captured(_) => return Err(Shape)
        }
      }
      columns.push(Flags(values, valid))
    } else {
      columns.push(
        Generic(
          FixedArray::makei(count, row => capture(input.rows[row][column])),
        ),
      )
    }
  }
  Ok({
    body: ColumnArrays(columns),
    width,
    count,
    selection: None,
    owned_selection: None,
  })
}

///|
fn layout_cell(input : LayoutStorage, row : Int, column : Int) -> Value? {
  if row < 0 || row >= input.count || column < 0 || column >= input.width {
    return None
  }
  guard layout_physical_row(input, row) is Some(at) else { return None }
  Some(
    match input.body {
      RowArrays(rows) => rows[at][column]
      ColumnArrays(columns) => layout_column_cell(columns[column], at)
      OwnedColumnArrays(columns) => {
        guard columns[column].value is Some(value) else { return None }
        layout_column_cell(value, at)
      }
    },
  )
}

///|
fn layout_physical_row(input : LayoutStorage, row : Int) -> Int? {
  if input.owned_selection is Some(handle) {
    guard handle.value is Some(indices) else { return None }
    return indices.get(row)
  }
  match input.selection {
    Some(indices) => indices.get(row)
    None => Some(row)
  }
}

///|
fn layout_column_cell(column : LayoutColumn, at : Int) -> Value {
  match column {
    Generic(values) => values[at]
    Numeric(values, valid) =>
      if valid[at] == 0 {
        Null
      } else {
        Number(values[at])
      }
    Flags(values, valid) =>
      if valid[at] == 0 {
        Null
      } else {
        Boolean(values[at] != 0)
      }
  }
}

///|
fn select_layout_rows(
  input : LayoutStorage,
  indices : Array[Int],
  b : LayoutAllocation,
) -> Result[LayoutStorage, LayoutStorageIssue] {
  if !reserve_slots(b.slots, indices.length()) ||
    !spend_control(b.work, indices.length()) {
    return Err(Limit)
  }
  for index in indices {
    if index < 0 || index >= input.count {
      return Err(Shape)
    }
  }
  match input.body {
    RowArrays(rows) =>
      Ok({
        body: RowArrays(indices.map(i => rows[i])),
        width: input.width,
        count: indices.length(),
        selection: None,
        owned_selection: None,
      })
    ColumnArrays(_) =>
      Ok({
        ..input,
        count: indices.length(),
        selection: Some(
          indices.map(i => input.selection.map(s => s[i]).unwrap_or(i)),
        ),
      })
    OwnedColumnArrays(columns) => {
      guard b.ledger is Some(ledger) else { return Err(Shape) }
      if !reserve_slots(b.slots, columns.length()) {
        return Err(Limit)
      }
      for index in indices {
        if layout_physical_row(input, index) is None {
          return Err(Shape)
        }
      }
      // Precharge the composed buffer while the old view remains live.
      let selection = match
        allocate_owned_layout_buffer(ledger, indices.length(), 0, fn() {
          indices.map(i => layout_physical_row(input, i).unwrap())
        }) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let shared = match
        share_layout_columns(columns, Array::makei(columns.length(), i => i), b) {
        Ok(v) => v
        Err(e) => {
          ignore(release_owned_layout_buffer(ledger, selection))
          return Err(e)
        }
      }
      Ok({
        ..input,
        body: OwnedColumnArrays(shared),
        count: indices.length(),
        selection: None,
        owned_selection: Some(selection),
      })
    }
  }
}

///|
fn project_layout(
  input : LayoutStorage,
  ordinals : Array[Int],
  b : LayoutAllocation,
) -> Result[LayoutStorage, LayoutStorageIssue] {
  if !reserve_slots(b.slots, ordinals.length()) ||
    !spend_control(b.work, ordinals.length()) {
    return Err(Limit)
  }
  for ordinal in ordinals {
    if ordinal < 0 || ordinal >= input.width {
      return Err(Shape)
    }
  }
  match input.body {
    RowArrays(rows) => {
      if !reserve_slots(b.slots, input.count) {
        return Err(Limit)
      }
      for _i = 0; _i < input.count; _i = _i + 1 {
        if !reserve_slots(b.slots, ordinals.length()) ||
          !spend_control(b.work, 1) ||
          !spend_control(b.work, ordinals.length()) {
          return Err(Limit)
        }
      }
      Ok({
        body: RowArrays(rows.map(row => ordinals.map(i => row[i]))),
        width: ordinals.length(),
        count: input.count,
        selection: None,
        owned_selection: None,
      })
    }
    ColumnArrays(columns) =>
      Ok({
        ..input,
        body: ColumnArrays(ordinals.map(i => columns[i])),
        width: ordinals.length(),
      })
    OwnedColumnArrays(columns) => {
      guard b.ledger is Some(ledger) else { return Err(Shape) }
      let selection = match input.owned_selection {
        None => None
        Some(handle) =>
          match share_owned_layout_buffer(ledger, handle) {
            Ok(shared) => Some(shared)
            Err(issue) => return Err(issue)
          }
      }
      match share_layout_columns(columns, ordinals, b) {
        Ok(shared) =>
          Ok({
            ..input,
            body: OwnedColumnArrays(shared),
            width: ordinals.length(),
            owned_selection: selection,
          })
        Err(e) => {
          if selection is Some(handle) {
            ignore(release_owned_layout_buffer(ledger, handle))
          }
          Err(e)
        }
      }
    }
  }
}

///|
fn layout_allocation(slots : Int, bytes : Int, work : Int) -> LayoutAllocation {
  {
    ledger: None,
    slots: { limit: slots, live: 0, peak: 0, },
    bytes: { limit: bytes, live: 0, peak: 0, },
    work: { remaining: work, max_frames: 0, },
  }
}

///|
test "A B C preserve captured numeric cells projection and composed occurrence order" {
  let owner = take_key_owner("[{\"take\":3}]")
  let captured = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":3,\"s\":\"three\"}"),
      input_cursor("{\"n\":1,\"s\":\"one\"}"),
      input_cursor("{\"n\":2,\"s\":\"two\"}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let budget = layout_allocation(1000, 1000, 1000)
    let original = import_layout(captured, candidate, budget).unwrap()
    let selected = select_layout_rows(original, [1, 2, 0, 1], budget).unwrap()
    let selected = select_layout_rows(selected, [3, 0, 2], budget).unwrap()
    assert_true(layout_cell(selected, 0, 0) is Some(Number(1)))
    assert_true(layout_cell(selected, 1, 0) is Some(Number(1)))
    assert_true(layout_cell(selected, 2, 0) is Some(Number(3)))
    let projected = project_layout(selected, [1, 0], budget).unwrap()
    assert_true(layout_cell(projected, 0, 0) is Some(Text("one")))
    assert_true(layout_cell(projected, 2, 1) is Some(Number(3)))
    let empty = project_layout(selected, [], budget).unwrap()
    assert_eq(empty.count, 3)
    assert_eq(empty.width, 0)
    assert_true(layout_cell(empty, 0, 0) is None)
    assert_true(layout_cell(original, 0, 0) is Some(Number(3)))
    assert_true(select_layout_rows(original, [3], budget) is Err(Shape))
    assert_true(project_layout(original, [2], budget) is Err(Shape))
    assert_true(
      import_layout(captured, candidate, layout_allocation(0, 0, 0))
      is Err(Limit),
    )
  }
}

///|
test "typed layout uses checked numeric boolean domains and separate NULL bytes" {
  for empty in [false, true] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"b\":{\"type\":\"boolean\",\"nullable\":true},\"n\":{\"type\":\"number\",\"nullable\":true}},\"rows\":" +
      (if empty {
        "[]"
      } else {
        "[{\"b\":false,\"n\":null},{\"b\":null,\"n\":3}]"
      }) +
      "},\"as\":\"seed\"}]",
    )
    let captured = capture_values(
      owner,
      0,
      max_rows=2,
      run_limits().input_values,
    ).unwrap()
    for candidate in [RowLayout, ValueColumns, TypedColumns] {
      let result = import_layout(
        captured,
        candidate,
        layout_allocation(100, 100, 100),
      ).unwrap()
      assert_eq(result.count, if empty { 0 } else { 2 })
      assert_eq(result.width, 2)
      if candidate == TypedColumns {
        guard result.body is ColumnArrays(columns) else { fail("columns") }
        assert_true(columns[0] is Flags(_, _))
        assert_true(columns[1] is Numeric(_, _))
      }
      if !empty {
        assert_true(layout_cell(result, 0, 0) is Some(Boolean(false)))
        assert_true(layout_cell(result, 0, 1) is Some(Null))
        assert_true(layout_cell(result, 1, 0) is Some(Null))
        assert_true(layout_cell(result, 1, 1) is Some(Number(3)))
      }
    }
    if !empty {
      // Source capture: 2 row slots + 2 schema slots + 4 value slots.
      // Destination: 2 column slots + (2*8+2) numeric bytes + (2+2) bool bytes.
      let exact = layout_allocation(10, 22, 12)
      assert_true(import_layout(captured, TypedColumns, exact) is Ok(_))
      assert_eq(exact.slots.peak, 10)
      assert_eq(exact.bytes.peak, 22)
      assert_eq(exact.work.remaining, 0)
      for limits in [(9, 22, 12), (10, 21, 12), (10, 22, 11)] {
        assert_true(
          import_layout(
            captured,
            TypedColumns,
            layout_allocation(limits.0, limits.1, limits.2),
          )
          is Err(Limit),
        )
      }
      assert_true(
        import_layout(captured, TypedColumns, layout_allocation(10, 22, 12))
        is Ok(_),
      )
    }
  }
}

///|
test "column projection retains only chosen buffers while small selections retain backing" {
  let captured = capture_values(
    sort_seed(""),
    0,
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  for candidate in [ValueColumns, TypedColumns] {
    let budget = layout_allocation(1000, 1000, 1000)
    let source = import_layout(captured, candidate, budget).unwrap()
    guard source.body is ColumnArrays(columns) else { fail("columns") }
    let projected = project_layout(source, [2], budget).unwrap()
    guard projected.body is ColumnArrays(kept) else { fail("columns") }
    assert_eq(kept.length(), 1)
    assert_true(physical_equal(kept[0], columns[2]))
    guard columns[2] is Generic(payload) else {
      fail("immutable payload fallback")
    }
    assert_eq(payload.length(), 3)
    let selected = select_layout_rows(projected, [2], budget).unwrap()
    assert_eq(selected.count, 1)
    guard selected.body is ColumnArrays(selected_columns) else {
      fail("columns")
    }
    assert_true(physical_equal(selected_columns[0], kept[0]))
    // A single logical row still keeps the full 3-row backing column alive.
    guard selected_columns[0] is Generic(backing) else { fail("payload") }
    assert_eq(backing.length(), 3)
    guard layout_cell(selected, 0, 0) is Some(Captured(@admitted.Array(values))) else {
      fail("payload")
    }
    assert_true(@admitted.element_at(values, 0) is Some(@admitted.Number(20)))
    let reversed = select_layout_rows(source, [2, 1, 0], budget).unwrap()
    let reversed = select_layout_rows(reversed, [2, 1, 0], budget).unwrap()
    assert_eq(reversed.selection.unwrap(), [0, 1, 2])
  }
}

///|
test "A B C use the same stable index kernel and consume identical comparison work" {
  let captured = capture_values(
    sort_seed(""),
    0,
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let order = [{ column: 1, descending: false, nulls_first: false, }]
  let mut reference_work = None
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let budget = layout_allocation(1000, 1000, 1000)
    let original = import_layout(captured, candidate, budget).unwrap()
    // k=[1,1,NULL], reordered to logical occurrences [1,0,2]. Stable ties
    // preserve this occurrence order, rather than physical backing row order.
    let input = select_layout_rows(original, [1, 0, 2], budget).unwrap()
    let control = { remaining: 1000, max_frames: 0, }
    let workspace = { limit: 1000, live: 0, peak: 0, }
    let indices = stable_order_indices(input, order, control, workspace).unwrap()
    assert_eq(indices, [0, 1, 2])
    assert_eq(workspace.live, 3)
    match reference_work {
      None => reference_work = Some(control.remaining)
      Some(expected) => assert_eq(control.remaining, expected)
    }
    let sorted = select_layout_rows(input, indices, budget).unwrap()
    assert_true(layout_cell(sorted, 0, 0) is Some(Number(1)))
    assert_true(layout_cell(sorted, 1, 0) is Some(Number(3)))
    let failed = { limit: 0, live: 0, peak: 0, }
    assert_true(
      stable_order_indices(
        input,
        order,
        { remaining: 1000, max_frames: 0, },
        failed,
      )
      is Err(Limit),
    )
    assert_eq(failed.live, 0)
  }
}

///|
test "zero-column nonempty import still consumes row work" {
  // Use an explicitly supplied typed empty relation, not author values syntax.
  let schema = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let owner = sort_input_owner(
    @pipeline.CarrierInput(@carrier.relation(@carrier.typed_rows(schema))),
    "[{\"drop\":[]}]",
  )
  let input = capture_input(
    owner,
    0,
    [input_cursor("{}"), input_cursor("{}")],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    assert_true(
      import_layout(input, candidate, layout_allocation(100, 0, 1))
      is Err(Limit),
    )
    let rows = import_layout(input, candidate, layout_allocation(100, 0, 100)).unwrap()
    assert_eq(rows.width, 0)
    assert_eq(rows.count, 2)
  }
}
