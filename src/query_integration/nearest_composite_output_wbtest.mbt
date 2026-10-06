///|
fn nearest_composite_source() -> @lower.BoundPrepared {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let fields : Array[(@schema.FieldName, @value_contract.Contract?)] = []
  let names : Array[@schema.FieldName] = []
  for index in 0..<12 {
    let name = "k" + index.to_string()
    fields.push((@schema.Unqualified(name), Some(number)))
    names.push(@schema.Unqualified(name))
  }
  fields.push(
    (
      @schema.Unqualified("embedding"),
      Some(@value_contract.vector_contract(2.0, nullable=false).unwrap()),
    ),
  )
  let rows = @carrier_contract.rows(
    fields,
    field_set=@carrier_contract.Closed,
    max_fields=13,
    max_name_bytes=100,
  ).unwrap()
  let vectors = @carrier_contract.vectors(
    rows,
    ids=names,
    components=@schema.Unqualified("embedding"),
    max_identity_fields=12,
  ).unwrap()
  direct_nearest_bind(
    @pipeline.check_carriers(
      input_cursor("[{\"from\":\"rows\",\"normalize_vectors\":true}]"),
      [("rows", vectors)],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
test "nearest incrementally encodes composite identity in canonical field order" {
  let source = nearest_composite_source()
  let output = @records.prepare_output(
    source,
    @pipeline.Step(0),
    { ..carrier_vectors_storage_limits(), max_fields_per_record: 13, },
    4096L,
    fn() { true },
  ).unwrap()
  let record : Array[(@schema.FieldName, @admitted.CheckedValue)] = []
  for index in 0..<12 {
    record.push(
      (
        @schema.Unqualified("k" + index.to_string()),
        direct_nearest_number(index.to_double()),
      ),
    )
  }
  record.push(
    (@schema.Unqualified("embedding"), direct_nearest_vector("[1,2]")),
  )
  @records.append_record(output, record).unwrap()
  let material = @records.completed_material(
    @records.finish_output(output).unwrap(),
  ).unwrap()
  let owner = direct_nearest_owner(source, source)
  let generated = task_test_generated(owner)
  let mut prior_work : Int64? = None
  for quantum in [1, 7] {
    let active = nearest_text_start(
      @bounded.control(),
      generated,
      owner,
      source,
      source,
      material,
      material,
      work=10000,
      workspace=1000,
    ).unwrap()
    let mut complete = false
    for _ in 0..<10000 {
      if !complete {
        match @local_veca.advance_nearest(active, quantum).unwrap() {
          @local_veca.NearestContinue(..) => ()
          @local_veca.NearestComplete(result, work~, ..) => {
            assert_eq(@execution.completed_row_count(result), 1)
            for column in [0, 1] {
              guard @execution.completed_cell(result, 0, column)
                is Some(Captured(@admitted.Object(fields))) else {
                fail("composite identity must remain a typed object")
              }
              for position, ordinal in [0, 1, 10, 11, 2, 3, 4, 5, 6, 7, 8, 9] {
                guard @admitted.element_at(fields, position)
                  is Some((name, value)) else {
                  fail("missing composite identity component")
                }
                assert_eq(name, ordinal.to_string())
                assert_true(
                  value is @admitted.Number(number) &&
                  number == ordinal.to_double(),
                )
              }
              assert_true(@admitted.element_at(fields, 12) is None)
            }
            assert_true(
              @execution.completed_cell(result, 0, 2) is Some(Number(1.0)),
            )
            assert_true(
              @execution.completed_cell(result, 0, 3) is Some(Number(5.0)),
            )
            if prior_work is Some(prior) {
              assert_eq(work, prior)
            }
            prior_work = Some(work)
            complete = true
          }
          _ => fail("valid composite nearest must complete")
        }
      }
    }
    assert_true(complete)
    assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
  }
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}
