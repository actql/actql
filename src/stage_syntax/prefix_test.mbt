///|
fn prefix_text() -> String {
  #|{"version":"actql/0.1","id":"prefix","stages":[{"id":"main","inputs":{},"steps":[],"results":{}}],"results":{}}
}

///|
test "generated check-only prefix preserves its Cursor without admitting a Program" {
  let source = generated_source(prefix_text(), limits())
  let prefix = admit_generated_prefix(source, limits()).unwrap()
  assert_true(physical_equal(prefix_body(prefix), @builder.cursor(source)))
  assert_eq(prefix_stages(prefix).length(), 1)
  assert_eq(result_names(prefix_stages(prefix)[0]), [])
  guard admit_generated_source(source, limits())
    is Err(Structure(EmptyDeclarations, path~, ..)) else {
    fail("ordinary complete Program admission remains strict")
  }
  assert_eq(path, [Key("stages"), Index(0), Key("results")])
  assert_true(parse(prefix_text(), limits(), format=Json)
    is Err(Structure(EmptyDeclarations, ..)))
}

///|
test "prefix envelope retains strict declarations and forbids publication roots" {
  for text in [
    prefix_text().replace(old="\"results\":{}", new="\"results\":{\"r\":{}}"),
    prefix_text().replace(old="\"inputs\":{}", new="\"inputs\":{},\"effects\":{\"e\":{}}"),
    prefix_text().replace(old="\"inputs\":{}", new="\"inputs\":{},\"table_inputs\":{\"t\":{}}"),
  ] {
    assert_true(admit_generated_prefix(generated_source(text, limits()), limits())
      is Err(Structure(PrefixPublication, ..)))
  }
  let absent = prefix_text().replace(old="\"inputs\":{},", new="")
  guard admit_generated_prefix(generated_source(absent, limits()), limits())
    is Err(Decode(issue)) else { fail("input envelope remains required") }
  assert_eq(issue.kind, @wire.MissingField)
  assert_true(admit_generated_prefix(generated_source(prefix_text(), limits()),
    { ..limits(), max_stages: 0, }) is Err(Structure(StageLimit, ..)))
}

///|
test "only the last Stage may remain an open prefix" {
  let open_stage = "{\"id\":\"first\",\"inputs\":{},\"steps\":[],\"results\":{}}"
  let text = prefix_text().replace(old="\"stages\":[", new="\"stages\":[" + open_stage + ",")
  guard admit_generated_prefix(generated_source(text, limits()), limits())
    is Err(Structure(EmptyDeclarations, path~, ..)) else {
    fail("earlier Stage is still a complete capture definition")
  }
  assert_eq(path, [Key("stages"), Index(0), Key("results")])
}
