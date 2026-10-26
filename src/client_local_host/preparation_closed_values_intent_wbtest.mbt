///|
fn intent_layout_test_input(
  text : String,
  fields : Int,
  rows : Int,
) -> ClientClosedValuesInputEnvelope {
  let f = closed_values_lexical_facts(text, text.length()).unwrap()
  {
    input_bytes_upper: f.input_bytes,
    node_upper: f.node_upper,
    objects: f.objects,
    arrays: f.arrays,
    fields_upper: f.fields_upper,
    quoted_tokens: f.quoted_tokens,
    quoted_utf16_units: f.quoted_utf16_units,
    longest_quoted_utf16: f.longest_quoted_utf16,
    longest_atom_utf16: f.longest_atom_utf16,
    depth_upper: f.depth_upper,
    fields,
    rows,
  }
}

///|
test "intent envelope adds exact ASCII wrapper and preserves original admission" {
  let text = "{\"x\":1}"
  let input = intent_layout_test_input(text, 1, 1)
  let quote = closed_values_intent_inventories(input).unwrap()
  let wire = "{\"input\":" + text + ",\"kind\":\"program\",\"parameters\":null}"
  let actual = closed_values_lexical_facts(wire, wire.length()).unwrap()
  assert_eq(quote._observed_wire_facts.input_bytes, wire.length())
  assert_eq(quote._observed_wire_facts.node_upper, actual.node_upper)
  assert_eq(
    quote._observed_wire_facts.quoted_utf16_units,
    actual.quoted_utf16_units,
  )
  assert_eq(quote._observed_wire_facts.depth_upper, actual.depth_upper)
  let intent = @publication_host.prepare_client_submitted_intent(
    wire,
    wire.length(),
    actual.node_upper,
    actual.depth_upper,
  ).unwrap()
  assert_eq(@publication_host.client_submitted_intent_wire(intent), wire)
  assert_true(
    closed_values_intent_inventories({ ..input, input_bytes_upper: 2147483647, })
    is None,
  )
  assert_true(
    closed_values_intent_inventories({ ..input, node_upper: 2147483647, })
    is None,
  )
}

///|
test "intent layout gives finite original numeric matrix phase envelope" {
  for (fields, rows) in [(1, 1), (100, 99)] {
    let schema : Array[String] = []
    let selected : Array[String] = []
    for i in 0..<fields {
      let name = "\"v" + i.to_string() + "\""
      schema.push(name + ":{\"type\":\"number\",\"nullable\":false}")
      selected.push(name)
    }
    let data : Array[String] = []
    for i in 0..<rows {
      let cells : Array[String] = []
      for j in 0..<fields {
        cells.push(selected[j] + ":" + (i + j).to_string())
      }
      data.push("{" + cells.join(",") + "}")
    }
    let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{" +
      schema.join(",") +
      "},\"rows\":[" +
      data.join(",") +
      "]},\"as\":\"v\"}],\"results\":{\"r\":{\"from\":\"v\",\"fields\":[" +
      selected.join(",") +
      "]}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
    let quote = closed_values_intent_inventories(
      intent_layout_test_input(text, fields, rows),
    ).unwrap()
    let retained = @execution.preparation_representation_cost(quote.retained).unwrap()
    let js = @execution.preparation_representation_cost(
      @execution.compose_preparation_representation([
        quote.shared_temporary,
        quote.js_temporary,
      ]).unwrap(),
    ).unwrap()
    let core = @execution.preparation_representation_cost(
      @execution.compose_preparation_representation([
        quote.shared_temporary,
        quote.core_temporary,
      ]).unwrap(),
    ).unwrap()
    let temporary = Int64::max(js, core)
    assert_true(retained > 0L && temporary > retained)
    println(
      "intent \{fields}x\{rows} source=\{text.length()} retained=\{retained} temporary=\{temporary}",
    )
  }
}

///|
test "intent phase quote keeps 100k original rows without retaining completed row controls" {
  let input : ClientClosedValuesInputEnvelope = {
    input_bytes_upper: 4301055,
    node_upper: 300048,
    objects: 100012,
    arrays: 4,
    fields_upper: 100022,
    quoted_tokens: 100031,
    quoted_utf16_units: 200154,
    longest_quoted_utf16: 13,
    longest_atom_utf16: 25,
    depth_upper: 8,
    fields: 1,
    rows: 100000,
  }
  let q = closed_values_intent_inventories(input).unwrap()
  assert_eq(
    q._observed_wire_facts,
    closed_values_intent_source_facts(input).unwrap(),
  )
  let js = @execution.preparation_representation_cost(
    @execution.compose_preparation_representation([
      q.shared_temporary,
      q.js_temporary,
    ]).unwrap(),
  ).unwrap()
  let core = @execution.preparation_representation_cost(
    @execution.compose_preparation_representation([
      q.shared_temporary,
      q.core_temporary,
    ]).unwrap(),
  ).unwrap()
  println("intent100k js=\{js} core=\{core} peak=\{Int64::max(js,core)}")
  assert_eq(js, 379324440L)
  assert_eq(core, 355812766L)
  assert_true(js > 0L && core > 0L)
  assert_true(Int64::max(js, core) < 536870912L)
  assert_true(Int64::max(js, core) < js + core)
  assert_true(closed_values_intent_source_facts({ ..input, rows: -1, }) is None)
  let bad : @execution.PreparationRepresentationUnits = {
    record_headers: 9223372036854775807L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  assert_true(closed_values_intent_scale_units(bad, 2L) is None)
}
