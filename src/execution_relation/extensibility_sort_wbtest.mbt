///|
// Private lifecycle trial. Appended chunks transfer their owned storage handles.
// The existing stable-sort selection kernel sees coordinates, not rebuilt rows.
priv struct ExtSortInput {
  owner : @lower.BoundPrepared
  id : String
  names : Array[String]
  chunks : Array[LayoutRelation]
  addresses : Array[(Int, Int)]
}

///|
impl IndexedRows for ExtSortInput with fn row_count(self) {
  self.addresses.length()
}

///|
impl IndexedRows for ExtSortInput with fn column_count(self) {
  self.names.length()
}

///|
impl IndexedRows for ExtSortInput with fn row_width(self, _row) {
  self.names.length()
}

///|
impl IndexedRows for ExtSortInput with fn read_cell(self, row, column) {
  let (chunk, row_in_chunk) = self.addresses[row]
  IndexedRows::read_cell(self.chunks[chunk], row_in_chunk, column)
}

///|
impl RelationRows for ExtSortInput with fn checked_owner(self) {
  self.owner
}

///|
impl RelationRows for ExtSortInput with fn relation_id(self) {
  self.id
}

///|
impl RelationRows for ExtSortInput with fn field_names(self) {
  self.names
}

///|
priv enum ExtSortPhase {
  Receiving
  Complete
  Disposed
} derive(Eq)

///|
priv struct ExtSort {
  input : ExtSortInput
  kernel : @lower.PreparedKernel
  ledger : LayoutLedger
  leases : Array[LayoutBufferLease]
  max_rows : Int
  mut phase : ExtSortPhase
  mut order : Array[Int]?
  mut next : Int
}

///|
fn ext_sort(
  kernel : @lower.PreparedKernel,
  model : LayoutRelation,
  ledger : LayoutLedger,
  max_rows : Int,
) -> ExtSort {
  {
    input: {
      owner: model.owner,
      id: model.id,
      names: model.names,
      chunks: [],
      addresses: [],
    },
    kernel,
    ledger,
    leases: [],
    max_rows,
    phase: Receiving,
    order: None,
    next: 0,
  }
}

///|
fn ext_sort_dispose(s : ExtSort) -> Unit {
  for chunk in s.input.chunks {
    release_layout_columns(chunk.storage)
  }
  s.input.chunks.clear()
  s.input.addresses.clear()
  s.order = None
  for lease in s.leases {
    ignore(release_layout_buffer(s.ledger, lease))
  }
  s.leases.clear()
  s.phase = Disposed
}

///|
fn ext_sort_append(
  s : ExtSort,
  chunk : LayoutRelation,
) -> Result[Unit, RowIssue] {
  let count = chunk.storage.count
  if s.phase != Receiving ||
    count < 0 ||
    !physical_equal(s.input.owner, chunk.owner) ||
    !physical_equal(@lower.kernel_owner(s.kernel), chunk.owner) ||
    chunk.id != s.input.id ||
    chunk.names != s.input.names ||
    chunk.storage.width != s.input.names.length() {
    release_layout_columns(chunk.storage)
    ext_sort_dispose(s)
    return Err(InvalidRows)
  }
  if count == 0 {
    release_layout_columns(chunk.storage)
    return Ok(())
  }
  if count > s.max_rows - s.input.addresses.length() || count > 536870910 {
    release_layout_columns(chunk.storage)
    ext_sort_dispose(s)
    return Err(RowLimit)
  }
  // Chunk handle, lease record and coordinate containers; conservative slots,
  // separate from both typed-buffer bytes and the kernel's own workspace.
  let lease = match allocate_layout_buffer(s.ledger, 2 + count * 4, 0) {
    Ok(v) => v
    Err(_) => {
      release_layout_columns(chunk.storage)
      ext_sort_dispose(s)
      return Err(RowLimit)
    }
  }
  if !spend_control(s.ledger.work, count) {
    ignore(release_layout_buffer(s.ledger, lease))
    release_layout_columns(chunk.storage)
    ext_sort_dispose(s)
    return Err(RowLimit)
  }
  s.leases.push(lease)
  let index = s.input.chunks.length()
  s.input.chunks.push(chunk)
  for row in 0..<count {
    s.input.addresses.push((index, row))
  }
  Ok(())
}

///|
fn ext_sort_end(
  s : ExtSort,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Unit, RowIssue] {
  if s.phase != Receiving {
    return Err(InvalidRows)
  }
  let lease = match
    allocate_layout_buffer(s.ledger, s.input.addresses.length() + 1, 0) {
    Ok(v) => v
    Err(_) => {
      ext_sort_dispose(s)
      return Err(RowLimit)
    }
  }
  s.leases.push(lease)
  match
    evaluate_sort_selection(
      s.kernel,
      s.input,
      s.max_rows,
      control,
      output,
      workspace,
    ) {
    Err(e) => {
      ext_sort_dispose(s)
      Err(e)
    }
    Ok(order) => {
      s.order = Some(order)
      s.phase = Complete
      Ok(())
    }
  }
}

///|
// Private bounded output cursor. Coordinates remain borrowed until disposal;
// no mutable buffer or partial result is handed to a product caller.
fn ext_sort_next(s : ExtSort, width : Int) -> Result[(Int, Int)?, RowIssue] {
  if s.phase != Complete || width <= 0 {
    return Err(InvalidRows)
  }
  let count = s.input.addresses.length()
  if s.next == count {
    return Ok(None)
  }
  let start = s.next
  let n = Int::min(width, count - start)
  s.next += n
  Ok(Some((start, n)))
}

///|
fn ext_sort_cell(s : ExtSort, row : Int, column : Int) -> Value? {
  if s.phase != Complete ||
    row < 0 ||
    row >= s.next ||
    column < 0 ||
    column >= s.input.names.length() {
    return None
  }
  guard s.order is Some(order) else { return None }
  Some(IndexedRows::read_cell(s.input, order[row], column))
}

///|
fn ext_sort_fixture(with_consumer? : Bool = false) -> LayoutRelation {
  let rows = Array::makei(15, i => {
    "{\"k\":" + (i % 3).to_string() + ",\"n\":" + i.to_string() + "}"
  })
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false},\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows.join(",") +
    "]},\"as\":\"seed\"},{\"sort\":[{\"k\":\"asc\"}]}" +
    (if with_consumer { ",{\"select\":[\"n\"]}" } else { "" }) +
    "]",
  )
  layout_relation(
    capture_values(owner, 0, max_rows=15, run_limits().input_values).unwrap(),
    TypedColumns,
  )
}

///|
fn ext_owned_sort_fixture(
  source : LayoutRelation,
  physical : LayoutAllocation,
) -> LayoutRelation {
  let schema = capture_values(
      source.owner,
      0,
      max_rows=15,
      run_limits().input_values,
    ).unwrap().schema
  let builder = layout_column_builder(
    schema,
    source.names,
    15,
    TypedColumns,
    physical,
  ).unwrap()
  for i in 0..<15 {
    append_layout_row(builder, [
      Number((i % 3).to_double()),
      Number(i.to_double()),
    ]).unwrap()
  }
  { ..source, storage: finish_layout_columns(builder).unwrap(), }
}

///|
test "chunk sort preserves cross-boundary ties and identical kernel charges" {
  let source = ext_sort_fixture()
  let kernel = row_kernel(source.owner, 1)
  let expected = [0, 3, 6, 9, 12, 1, 4, 7, 10, 13, 2, 5, 8, 11, 14]
  let baseline_control = { remaining: 100000, max_frames: 100, }
  let baseline_workspace = { limit: 100000, live: 0, peak: 0, }
  assert_eq(
    evaluate_sort_selection(
      kernel,
      source,
      15,
      baseline_control,
      row_output(),
      baseline_workspace,
    ).unwrap(),
    expected,
  )
  for width in [1, 7, 1000] {
    let ledger = layout_ledger(1000, 10000, 10000)
    let physical = {
      ..layout_allocation(10000, 10000, 10000),
      ledger: Some(ledger),
    }
    let source = ext_owned_sort_fixture(source, physical)
    let s = ext_sort(kernel, source, ledger, 15)
    let mut at = 0
    while at < 15 {
      let n = Int::min(width, 15 - at)
      let storage = select_layout_rows(
        source.storage,
        Array::makei(n, i => at + i),
        physical,
      ).unwrap()
      ext_sort_append(s, { ..source, storage, }).unwrap()
      assert_true(ext_sort_cell(s, 0, 0) is None)
      at += n
    }
    release_layout_columns(source.storage)
    assert_eq(ledger.bytes.live, 270)
    let control = { remaining: 100000, max_frames: 100, }
    let workspace = { limit: 100000, live: 0, peak: 0, }
    ext_sort_end(s, control, row_output(), workspace).unwrap()
    assert_eq(s.order.unwrap(), expected)
    assert_eq(
      (control.remaining, workspace.peak),
      (baseline_control.remaining, baseline_workspace.peak),
    )
    while ext_sort_next(s, width).unwrap() is Some((start, n)) {
      for row in start..<(start + n) {
        assert_true(
          ext_sort_cell(s, row, 1) is Some(Number(v)) &&
          v == expected[row].to_double(),
        )
      }
    }
    ext_sort_dispose(s)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  }
}

///|
test "chunk sort aborts retained chunks on late append or kernel failure" {
  let source = ext_sort_fixture()
  let kernel = row_kernel(source.owner, 1)
  for late_append in [true, false] {
    let ledger = layout_ledger(1000, 10000, 10000)
    let physical = {
      ..layout_allocation(10000, 10000, 10000),
      ledger: Some(ledger),
    }
    let s = ext_sort(kernel, source, ledger, if late_append { 7 } else { 15 })
    let first = select_layout_rows(
      source.storage,
      [0, 1, 2, 3, 4, 5, 6],
      physical,
    ).unwrap()
    ext_sort_append(s, { ..source, storage: first, }).unwrap()
    assert_true(ledger.slots.live > 0)
    if late_append {
      let second = select_layout_rows(source.storage, [7], physical).unwrap()
      assert_true(
        ext_sort_append(s, { ..source, storage: second, }) is Err(RowLimit),
      )
    } else {
      assert_true(
        ext_sort_end(s, { remaining: 0, max_frames: 100, }, row_output(), {
          limit: 100000,
          live: 0,
          peak: 0,
        })
        is Err(RowLimit),
      )
    }
    assert_true(ext_sort_next(s, 1) is Err(InvalidRows))
    assert_true(ext_sort_cell(s, 0, 0) is None)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    assert_eq(s.input.chunks.length(), 0)
    ext_sort_dispose(s)
    assert_eq(ledger.slots.live, 0)
  }
}

///|
test "stateful sort gates output and matches row kernel across chunk widths" {
  let owner = sort_seed(",{\"sort\":[{\"id\":\"asc\"}]}")
  let source = layout_relation(
    capture_values(owner, 0, max_rows=3, run_limits().input_values).unwrap(),
    TypedColumns,
  )
  let kernel = row_kernel(owner, 1)
  for width in [1, 7, 1000] {
    let ledger = layout_ledger(1000, 10000, 10000)
    let physical = {
      ..layout_allocation(10000, 10000, 10000),
      ledger: Some(ledger),
    }
    let s = ext_sort(kernel, source, ledger, 3)
    assert_true(ext_sort_next(s, width) is Err(InvalidRows))
    assert_true(ext_sort_cell(s, 0, 0) is None)
    let mut at = 0
    while at < 3 {
      let n = Int::min(width, 3 - at)
      let storage = select_layout_rows(
        source.storage,
        Array::makei(n, i => at + i),
        physical,
      ).unwrap()
      ext_sort_append(s, { ..source, storage, }).unwrap()
      at += n
    }
    ext_sort_end(s, { remaining: 100000, max_frames: 100, }, row_output(), {
      limit: 100000,
      live: 0,
      peak: 0,
    }).unwrap()
    assert_eq(s.order.unwrap(), [1, 2, 0])
    while ext_sort_next(s, width).unwrap() is Some((start, n)) {
      for row in start..<(start + n) {
        assert_true(
          ext_sort_cell(s, row, 0) is Some(Number(v)) &&
          v == (row + 1).to_double(),
        )
      }
    }
    assert_true(
      ext_sort_end(s, { remaining: 100000, max_frames: 100, }, row_output(), {
        limit: 100000,
        live: 0,
        peak: 0,
      })
      is Err(InvalidRows),
    )
    ext_sort_dispose(s)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    assert_true(ext_sort_cell(s, 0, 0) is None)
  }
}
