///|
// A synchronous borrow of a successfully finished private sort. This is not
// CompletedOutput and cannot be supplied to product producer admission.
priv struct ExtSortedRows {
  producer : ExtSort
  id : String
}

///|
fn ext_consumer_budget(work : Int64, live? : Int64 = 10000L) -> LogicalBudget {
  logical_budget(
    {
      max_input_rows: 15L,
      max_value_bytes: 1000L,
      max_live_value_bytes: live,
      max_work: work,
    },
    10000,
    10000,
    100,
  ).unwrap()
}

///|
impl IndexedRows for ExtSortedRows with fn row_count(self) {
  self.producer.input.addresses.length()
}

///|
impl IndexedRows for ExtSortedRows with fn column_count(self) {
  self.producer.input.names.length()
}

///|
impl IndexedRows for ExtSortedRows with fn row_width(self, _row) {
  self.producer.input.names.length()
}

///|
impl IndexedRows for ExtSortedRows with fn read_cell(self, row, column) {
  IndexedRows::read_cell(
    self.producer.input,
    self.producer.order.unwrap()[row],
    column,
  )
}

///|
impl RelationRows for ExtSortedRows with fn checked_owner(self) {
  self.producer.input.owner
}

///|
impl RelationRows for ExtSortedRows with fn relation_id(self) {
  self.id
}

///|
impl RelationRows for ExtSortedRows with fn field_names(self) {
  self.producer.input.names
}

///|
fn ext_consume_sorted(
  s : ExtSort,
  kernel : @lower.PreparedKernel,
  physical : LayoutAllocation,
  logical : LogicalBudget,
) -> Result[LayoutStorage, RowIssue] {
  if s.phase != Complete {
    return Err(InvalidRows)
  }
  let id = @lower.node_id(
    @lower.node_at(
      @lower.bound_preparation(s.input.owner),
      @lower.kernel_step(s.kernel),
    ).unwrap(),
  )
  if !physical_equal(@lower.kernel_owner(kernel), s.input.owner) {
    return Err(OwnerMismatch)
  }
  if @lower.kernel_input(kernel) != id {
    return Err(InputMismatch)
  }
  // The producer stays borrowed until the entire synchronous consumer returns.
  let input = ExtSortedRows::{ producer: s, id, }
  let schema = @relation.output_schema(@lower.kernel_checked(kernel))
  let names = Array::makei(@schema.field_count(schema), i => {
    @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
  })
  let builder = match
    layout_column_builder(
      schema,
      names,
      s.input.addresses.length(),
      TypedColumns,
      physical,
    ) {
    Ok(b) => b
    Err(e) => return Err(e)
  }
  let result = evaluate_row_body_into(
    PreparedBody(kernel),
    input,
    15,
    { remaining: 100000, max_frames: 100, },
    row_output(),
    { limit: 100000, live: 0, peak: 0, },
    fn(row, _source, _names, _projection) { append_layout_row(builder, row) },
    ordered_budget=Some(logical),
  )
  match result {
    Err(e) => {
      abort_layout_columns(builder)
      Err(e)
    }
    Ok(_) => finish_layout_columns(builder)
  }
}

///|
test "typed inlet through completed chunk sort feeds checked column consumer" {
  let model = ext_sort_fixture(with_consumer=true)
  let schema = @relation.input_schema(
    @lower.kernel_checked(row_kernel(model.owner, 1)),
  )
  let expected = [0, 3, 6, 9, 12, 1, 4, 7, 10, 13, 2, 5, 8, 11, 14]
  for width in [1, 7, 1000] {
    let ledger = layout_ledger(10000, 10000, 100000)
    let physical = {
      ..layout_allocation(100000, 100000, 100000),
      ledger: Some(ledger),
    }
    let source = ext_number_source(
      [
        {
          values: Array::makei(15, i => (i % 3).to_double()),
          valid: Array::make(15, 1),
        },
        {
          values: Array::makei(15, i => i.to_double()),
          valid: Array::make(15, 1),
        },
      ],
      ledger,
    ).unwrap()
    let storage = ext_admit_owned_numbers(
      schema,
      model.names,
      source,
      15,
      15,
      ledger,
    ).unwrap()
    let input = { ..model, storage, }
    release_owned_layout_buffer(ledger, source).unwrap()
    let s = ext_sort(row_kernel(model.owner, 1), input, ledger, 15)
    let consumer = row_kernel(model.owner, 2)
    assert_true(
      ext_consume_sorted(
        s,
        consumer,
        physical,
        ordered_row_budget(10000L, 10000L),
      )
      is Err(InvalidRows),
    )
    let mut at = 0
    while at < 15 {
      let n = Int::min(width, 15 - at)
      let chunk = select_layout_rows(
        input.storage,
        Array::makei(n, i => at + i),
        physical,
      ).unwrap()
      ext_sort_append(s, { ..input, storage: chunk, }).unwrap()
      at += n
    }
    release_layout_columns(input.storage)
    ext_sort_end(s, { remaining: 100000, max_frames: 100, }, row_output(), {
      limit: 100000,
      live: 0,
      peak: 0,
    }).unwrap()
    let before = (ledger.slots.live, ledger.bytes.live)
    for (work, live) in [(0L, 10000L), (134L, 10000L), (135L, 206L)] {
      let fail_budget = ext_consumer_budget(work, live~)
      let result = ext_consume_sorted(s, consumer, physical, fail_budget)
      if live == 206L {
        assert_true(result is Err(LogicalRows(LiveValueLimit)))
      } else if work == 134L {
        assert_true(result is Err(LogicalRows(ValueMeasure(LogicalWorkLimit))))
      } else {
        assert_true(result is Err(LogicalRows(WorkLimit)))
      }
      assert_eq(fail_budget.live, 0L)
      assert_eq((ledger.slots.live, ledger.bytes.live), before)
    }
    // A failed consumer does not dispose or silently rerun the producer.
    assert_true(s.phase == Complete)
    // Independent formula: 15*(input object+2 keys+2 values)=75;
    // 15 row entries + 15*(output object+key+value)=60. Input wire roots
    // total 200 bytes and coexist with the first 7-byte output root.
    let logical = ext_consumer_budget(135L, live=207L)
    let output = ext_consume_sorted(s, consumer, physical, logical).unwrap()
    assert_eq((logical.work, logical.peak, logical.live), (135L, 207L, 0L))
    ext_sort_dispose(s)
    assert_eq(ledger.bytes.live, 135)
    for i in 0..<15 {
      assert_true(
        layout_cell(output, i, 0) is Some(Number(n)) &&
        n == expected[i].to_double(),
      )
    }
    assert_true(output.body is OwnedColumnArrays(_))
    release_layout_columns(output)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  }
}
