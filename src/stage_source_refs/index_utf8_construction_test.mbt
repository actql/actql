///|
fn index_name_source(name : String) -> @stages.Source {
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"" +
    name +
    "\":\"relation\"},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
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
test "Source index backs one UTF8 call frame without multiplying borrowed name length" {
  let ascii = index_name_source("abc")
  let unicode = index_name_source("é😀")
  let longer = index_name_source("é😀".repeat(30))
  let a = observe_index_construction_geometry(ascii, caps())
  let u = observe_index_construction_geometry(unicode, caps())
  let l = observe_index_construction_geometry(longer, caps())
  assert_eq(a, u)
  assert_eq(u, l)
  let quoted = index_construction_inventory(a, caps()).unwrap()
  assert_eq(quoted, index_construction_inventory(u, caps()).unwrap())
  assert_eq(quoted, index_construction_inventory(l, caps()).unwrap())
  // Stage id is one byte; the single input is two plus four UTF8 bytes.
  // Existing admission is atomic per name, so the failed name contributes
  // no admitted bytes while already charged Stage/input work stays spent.
  let (result, used) = observe_prepare(unicode, { ..caps(), max_text_bytes: 7, })
  assert_true(result is Ok(_))
  assert_eq(used, { work: 2, text_bytes: 7, })
  let (result, used) = observe_prepare(unicode, { ..caps(), max_text_bytes: 6, })
  assert_true(result is Err(BudgetExceeded))
  assert_eq(used, { work: 2, text_bytes: 1, })
}
