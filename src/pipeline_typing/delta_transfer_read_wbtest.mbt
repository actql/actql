///|
fn original_transfer_delta(
  b : Budget,
  source : @decode.Cursor,
  previous : DeltaEvidence,
  op : @relation.CheckedOperation,
) -> DeltaEvidence raise Stop {
  if previous.fields.is_empty() {
    return previous
  }
  match @relation.operation(op) {
    Filter
    | Sort
    | Take
    | AssertRows
    | DedupeRows
    | TopK
    | TopKBy
    | Lag
    | WatermarkRows => previous
    Derive => {
      spend(b, source, @relation.binding_count(op) + previous.fields.length())
      let overwritten : Map[String, Bool] = Map([])
      for i in 0..<@relation.binding_count(op) {
        if @relation.binding_at(op, i).unwrap().name is Some(name) {
          overwritten[name] = true
        }
      }
      let fields : Map[String, @graph_contract.CheckedContract] = Map([])
      for key, value in previous.fields {
        if !overwritten.contains(key) {
          fields[key] = value
        }
      }
      { fields, }
    }
    Select | Rename | Drop | Distinct => {
      if @relation.row_operation(op) is Some(DistinctRows) {
        return previous
      }
      let projection = @relation.projection(op)
      spend(b, source, projection.length())
      let fields : Map[String, @graph_contract.CheckedContract] = Map([])
      for p in projection {
        if previous.fields.get(@schema.reference_name(p.input)) is Some(c) {
          let name = @schema.reference_name(p.output)
          charge(b, source, name)
          fields[name] = c
        }
      }
      { fields, }
    }
    _ => empty_delta()
  }
}

///|
fn delta_transfer_operation(text : String) -> @relation.CheckedOperation {
  let carrier = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_fields(
        [
          (
            @schema.Unqualified("delta"),
            @contract.primitive(JsonType, nullable=false),
          ),
          (
            @schema.Unqualified("keep"),
            @contract.primitive(JsonType, nullable=false),
          ),
        ],
        max_fields=2,
        max_name_bytes=9,
      ).unwrap(),
    ),
  )
  let checked = check_carriers(
    evidence_read_cursor(text),
    [("rows", carrier)],
    None,
    None,
    evidence_read_limits(),
  ).unwrap()
  guard step_at(checked, 0).unwrap().operation is Unary(op) else {
    abort("original unary expected")
  }
  op
}

///|
fn delta_transfer_budget(work? : Int = 10000, text? : Int = 10000) -> Budget {
  { limits: evidence_read_limits(), work, text, nodes: 10000, tokens: 10000, }
}

///|
fn delta_transfer_evidence() -> DeltaEvidence raise {
  let original = imported_graph_contract()
  { fields: Map([("delta", original), ("keep", original)]), }
}

///|
test "original Delta derive transfer retains the same Map contracts and ordered overwrite work across returns" {
  let op = delta_transfer_operation(
    "[{\"derive\":[{\"delta\":\"1\"},{\"extra\":\"2\"}]}]",
  )
  let previous = delta_transfer_evidence()
  let source = @relation.source(op)
  let b = delta_transfer_budget()
  let reference = delta_transfer_budget()
  let expected = original_transfer_delta(reference, source, previous, op) catch {
    Stop(_) => abort("original transfer expected")
  }
  let read = begin_delta_transfer_read(b, source, previous, op)
  assert_true(take_delta_transfer_read(read) is None)
  guard read.state is Pending(body) else {
    abort("original transfer body expected")
  }
  assert_true(physical_equal(body.b, b))
  assert_true(physical_equal(body.source, source))
  assert_true(physical_equal(body.previous, previous))
  assert_true(physical_equal(body.op, op))
  let mut constructors = 0
  while read.state is Pending(_) {
    advance_delta_transfer_read(read)
    constructors += 1
  }
  assert_eq(constructors, 5) // Select + two names + two original fields.
  let actual = take_delta_transfer_read(read).unwrap().unwrap()
  assert_eq(b.work, reference.work)
  assert_eq(b.work, 9996)
  assert_eq(b.text, reference.text)
  assert_eq(actual.fields.length(), 1)
  assert_true(actual.fields.get("delta") is None)
  assert_true(physical_equal(actual.fields["keep"], previous.fields["keep"]))
  assert_true(physical_equal(actual.fields["keep"], expected.fields["keep"]))
  assert_false(physical_equal(actual.fields, previous.fields))
  assert_eq(previous.fields.length(), 2)
  clear_delta_transfer_read(read)
  assert_true(take_delta_transfer_read(read) is None)
}

///|
test "original Delta projection charges exact output spelling and retains partial failure without visiting later fields" {
  let op = delta_transfer_operation(
    "[{\"select\":[{\"saved\":\"delta\"},{\"saved_again\":\"keep\"}]}]",
  )
  let previous = delta_transfer_evidence()
  for text in [16, 15] {
    let b = delta_transfer_budget(work=2, text~)
    let reference = delta_transfer_budget(work=2, text~)
    let expected = Ok(
      original_transfer_delta(reference, @relation.source(op), previous, op),
    ) catch {
      Stop(issue) => Err(issue)
    }
    let read = begin_delta_transfer_read(b, @relation.source(op), previous, op)
    while read.state is Pending(_) {
      advance_delta_transfer_read(read)
    }
    assert_eq(b.work, reference.work)
    assert_eq(b.text, reference.text)
    if text == 16 {
      let actual = take_delta_transfer_read(read).unwrap().unwrap()
      assert_eq(actual.fields.length(), 2)
      assert_true(
        physical_equal(actual.fields["saved"], previous.fields["delta"]),
      )
      assert_true(
        physical_equal(actual.fields["saved_again"], previous.fields["keep"]),
      )
      assert_eq(expected.unwrap().fields.length(), 2)
    } else {
      guard read.state is Rejected(body, issue) else {
        abort("same short refusal expected")
      }
      assert_eq(issue.kind, expected.unwrap_err().kind)
      assert_eq(issue.kind, BudgetExceeded)
      assert_eq(body.fields.unwrap().length(), 1)
      assert_true(body.fields.unwrap().get("saved_again") is None)
      let work = b.work
      let bytes = b.text
      advance_delta_transfer_read(read)
      assert_eq(b.work, work)
      assert_eq(b.text, bytes)
      clear_delta_transfer_read(read)
      assert_true(body.fields is None)
      assert_true(body.projection is None)
      assert_true(take_delta_transfer_read(read) is None)
    }
  }
}

///|
test "original Delta identity and empty fast paths borrow the same evidence and clear prevents pending Map writes" {
  let op = delta_transfer_operation("[{\"filter\":\"TRUE\"}]")
  for previous in [empty_delta(), delta_transfer_evidence()] {
    let b = delta_transfer_budget(work=0, text=0)
    let read = begin_delta_transfer_read(b, @relation.source(op), previous, op)
    advance_delta_transfer_read(read)
    let actual = take_delta_transfer_read(read).unwrap().unwrap()
    assert_true(physical_equal(actual, previous))
    assert_eq(b.work, 0)
    assert_eq(b.text, 0)
  }
  let derived_op = delta_transfer_operation(
    "[{\"derive\":[{\"delta\":\"1\"}]}]",
  )
  let previous = delta_transfer_evidence()
  let b = delta_transfer_budget()
  let read = begin_delta_transfer_read(
    b,
    @relation.source(derived_op),
    previous,
    derived_op,
  )
  advance_delta_transfer_read(read)
  guard read.state is Pending(body) else { abort("pending name expected") }
  assert_true(body.overwritten is Some(_))
  assert_true(body.fields is None)
  let work = b.work
  clear_delta_transfer_read(read)
  advance_delta_transfer_read(read)
  assert_true(body.overwritten is None)
  assert_true(body.iterator is None)
  assert_true(body.pending is None)
  assert_eq(b.work, work)
  assert_eq(previous.fields.length(), 2)
}
