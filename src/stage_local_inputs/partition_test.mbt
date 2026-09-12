///|
fn mixed_source(remote : String) -> @stages.Source {
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"rows\":\"relation\",\"remote\":" +
    remote +
    "},\"steps\":[],\"results\":{\"out\":{}}},{\"id\":\"t\",\"inputs\":{\"remote\":\"relation\"},\"steps\":[],\"results\":{\"out\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"t\",\"result\":\"out\"}}}}",
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
test "mixed input partition retains the exact SourceView owner and stage scope" {
  let wire = "{\"connector\":\"crm\",\"resource\":\"rows\"}"
  let source = mixed_source(wire)
  let views = @sourceviews.collect(source, {
    max_work: 10000,
    max_order_keys: 10,
  }).unwrap()
  assert_true(
    physical_equal(
      @sourceviews.input_for(views, 0, "remote").unwrap(),
      @sourceviews.at(views, 0).unwrap(),
    ),
  )
  assert_true(@sourceviews.input_for(views, 1, "remote") is None)
  assert_true(@sourceviews.input_for(views, -1, "remote") is None)
  assert_true(@sourceviews.input_for(views, 0, "missing") is None)
  assert_true(prepare(source, 0, caps()) is Err(Declaration("remote", _)))
  let prepared = prepare(source, 0, caps(), sourceviews=Some(views)).unwrap()
  assert_eq(count(prepared), 1)
  assert_eq(entry_at(prepared, 0).unwrap().0, "rows")
  assert_true(physical_equal(sourceview_inputs(prepared).unwrap(), views))
  let next = prepare(source, 1, caps(), sourceviews=Some(views)).unwrap()
  assert_eq(count(next), 1)
  assert_eq(entry_at(next, 0).unwrap().0, "remote")
  assert_true(
    prepare(mixed_source(wire), 0, caps(), sourceviews=Some(views))
    is Err(ForeignSourceViews),
  )
  let used = usage(prepared)
  let exact = {
    ..caps(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(prepare(source, 0, exact, sourceviews=Some(views)) is Ok(_))
  assert_true(
    prepare(
      source,
      0,
      { ..exact, max_work: used.work - 1, },
      sourceviews=Some(views),
    )
    is Err(_),
  )
  assert_true(sourceview_inputs(prepare(parsed(), 0, caps()).unwrap()) is None)
}

///|
test "SourceView partition cannot skip an invalid Connector declaration" {
  let source = mixed_source(
    "{\"connector\":\"crm\",\"resource\":\"rows\",\"schema\":{}}",
  )
  assert_true(
    @sourceviews.collect(source, { max_work: 10000, max_order_keys: 10, })
    is Err(_),
  )
  assert_true(prepare(source, 0, caps()) is Err(Declaration("remote", _)))
}

///|
test "SourceView partition does not hide unsupported local carriers" {
  let source = mixed_source("\"events\"")
  let views = @sourceviews.collect(source, {
    max_work: 10000,
    max_order_keys: 10,
  }).unwrap()
  assert_eq(@sourceviews.count(views), 0)
  assert_true(
    prepare(source, 0, caps(), sourceviews=Some(views))
    is Err(Declaration("remote", @local_input.UnsupportedCarrier("events"))),
  )
}
