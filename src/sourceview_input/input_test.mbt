///|
fn owner(input : String, second? : String = "") -> @stages.Source {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":" +
    input +
    ",\"local\":\"relation\"},\"steps\":[],\"results\":{\"r\":{}}}" +
    second +
    "],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
  let program = @stage.parse(
    text,
    {
      source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 20000, },
      tree: {
        max_nodes: 100000,
        max_depth: 20000,
        max_string_bytes: 1000000,
        max_total_string_bytes: 1000000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  @stages.prepare(program, {
    max_parameters: 0,
    max_nodes: 100,
    max_depth: 100,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
fn caps() -> Limits {
  { max_work: 1000000, max_order_keys: 100, }
}

///|
test "SourceView inputs retain unresolved selectors and opaque request data" {
  let source = owner(
    (
      #|{"connector":"crm/main","resource":"records","request":{"opaque":{"nested":{"$param":"not_a_reference"}}},"minimum_classification":"restricted","meta":{"free":{"actql_nested":true}}}
    ),
  )
  let inputs = collect(source, caps()).unwrap()
  assert_true(physical_equal(@sourceview_input.source(inputs), source))
  assert_eq(count(inputs), 1)
  let input = at(inputs, 0).unwrap()
  assert_eq(input.connector, "crm/main")
  assert_eq(input.resource, "records")
  assert_eq(input.input_name, "remote")
  assert_eq(input.stage_index, 0)
  assert_true(input.view is None)
  assert_true(input.scan is None)
  assert_eq(input.minimum_classification, Some("restricted"))
  assert_eq(@decode.object_length(input.request.unwrap()), Some(1))
  assert_true(at(inputs, -1) is None)
  assert_true(at(inputs, 1) is None)
  assert_true(collect(source, { ..caps(), max_work: work(inputs), }) is Ok(_))
  assert_true(
    collect(source, { ..caps(), max_work: work(inputs) - 1, }) is Err(WorkLimit),
  )
}

///|
test "source syntax is closed and optional null never means omission" {
  for
    input in [
      "{\"connector\":\"c\"}", "{\"resource\":\"r\"}", "{\"connector\":\"\",\"resource\":\"r\"}",
      "{\"connector\":\"c\",\"resource\":null}",
    ] {
    assert_true(collect(owner(input), caps()) is Err(_))
  }
  for
    extra in [
      "\"view\":null", "\"view\":\"\"", "\"request\":{}", "\"request\":null", "\"scan\":{}",
      "\"scan\":{\"mode\":\"other\"}", "\"scan\":{\"mode\":\"snapshot\",\"extra\":1}",
      "\"schema\":{}", "\"carrier\":\"relation\"", "\"schema_ref\":\"x\"", "\"expected_columns\":[]",
      "\"minimum_classification\":\"Public\"", "\"minimum_classification\":null",
      "\"meta\":{}", "\"meta\":{\"actql_reserved\":1}", "\"extra\":1", "\"duplicates\":\"first_by_order\"",
      "\"duplicates\":{\"first_by_order\":{\"order_by\":[]}}",
    ] {
    assert_true(
      collect(
        owner("{\"connector\":\"c\",\"resource\":\"r\"," + extra + "}"),
        caps(),
      )
      is Err(_),
    )
  }
  assert_true(
    collect(owner("{\"connector\":\"c\",\"resource\":\"r\"}"), {
      ..caps(),
      max_work: -1,
    })
    is Err(InvalidLimits),
  )
}

///|
test "scan and duplicate terms are retained without claiming acquisition compatibility" {
  let second =
    #|,{"id":"b","inputs":{"prior":{"result":{"stage":"a","result":"r"}},"remote":{"connector":"c","resource":"r","view":"v","scan":{"mode":"changes"},"duplicates":"reject"}},"steps":[],"results":{"r":{}}}
  let input =
    #|{"connector":"c","resource":"r","view":"v","scan":{"mode":"snapshot"},"duplicates":{"first_by_order":{"order_by":[{"id":"asc"},{"id":"asc"}]}}}
  let source = owner(input, second~)
  let inputs = collect(source, caps()).unwrap()
  assert_eq(count(inputs), 2)
  let first = at(inputs, 0).unwrap()
  assert_eq(first.view, Some("v"))
  assert_eq(first.scan, Some(Snapshot))
  assert_eq(at(inputs, 1).unwrap().scan, Some(Changes))
  assert_eq(at(inputs, 1).unwrap().stage_index, 1)
  let terms = first_by_order(first).unwrap()
  assert_eq(terms.length(), 2)
  terms.clear()
  assert_eq(first_by_order(first).unwrap().length(), 2)
  assert_true(
    collect(source, { ..caps(), max_order_keys: 1, }) is Err(OrderLimit),
  )
  assert_true(collect(source, { ..caps(), max_order_keys: 2, }) is Ok(_))
}

///|
test "request and metadata traversal is bounded and nonrecursive" {
  let deep = "[".repeat(10000) + "null" + "]".repeat(10000)
  let source = owner(
    "{\"connector\":\"c\",\"resource\":\"r\",\"request\":{\"data\":" +
    deep +
    "}}",
  )
  let inputs = collect(source, caps()).unwrap()
  assert_eq(count(inputs), 1)
  assert_true(
    collect(source, { ..caps(), max_work: work(inputs) - 1, }) is Err(WorkLimit),
  )
}

///|
test "collection observer retains original Source and independently counted work" {
  let original = owner("{\"connector\":\"c\",\"resource\":\"r\"}")
  // Stage1 + input slots2 + names6+5 + remote fields2 + body preflight24 =40.
  let (result, spent) = observe_collect(original, {
    max_work: 40,
    max_order_keys: 0,
  })
  let inputs = result.unwrap()
  assert_eq(spent, 40)
  assert_eq(work(inputs), 40)
  assert_true(physical_equal(source(inputs), original))
  assert_eq(count(inputs), 1)
  let declaration = at(inputs, 0).unwrap()
  assert_eq(declaration.connector, "c")
  assert_eq(declaration.resource, "r")
  assert_true(
    physical_equal(input_for(inputs, 0, "remote").unwrap(), declaration),
  )
}

///|
test "collection observer retains failed work prefix without charging unperformed work" {
  let original = owner("{\"connector\":\"c\",\"resource\":\"r\"}")
  for (limit, expected) in [(39, 35), (10, 9), (0, 0)] {
    let (result, spent) = observe_collect(original, {
      max_work: limit,
      max_order_keys: 0,
    })
    assert_true(result is Err(WorkLimit))
    assert_eq(spent, expected)
  }
  let malformed = owner("{\"connector\":\"\",\"resource\":\"r\"}")
  let (result, spent) = observe_collect(malformed, caps())
  assert_true(result is Err(InvalidValue(at)) && @decode.text(at) == Ok(""))
  // Before the local name: stage1+slots2+remote name6+fields2+preflight23.
  assert_eq(spent, 34)
}

///|
test "collection observer invalid limits retain exact refusal with no reader work" {
  let original = owner("{\"connector\":\"c\",\"resource\":\"r\"}")
  let cases : Array[Limits] = [
    { max_work: -1, max_order_keys: 0, },
    { max_work: 40, max_order_keys: -1, },
  ]
  for limits in cases {
    let (result, spent) = observe_collect(original, limits)
    assert_true(result is Err(InvalidLimits))
    assert_eq(spent, 0)
    assert_true(collect(original, limits) is Err(InvalidLimits))
  }
}
