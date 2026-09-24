///|
test "source-free unit extraction keeps Values and strips annotations" {
  let source =
    #|{"version":"actql/0.1","id":"outer","meta":{"note":"author"},"stages":[{"id":"source","meta":{"note":"stage"},"inputs":{},"steps":[{"values":{"rows":[{"meta":{"business":true},"id":1}]},"as":"rows","meta":{"note":"step"}}],"results":{"answer":{"from":"rows","meta":{"note":"result"}}}}],"results":{"published":{"from":{"stage":"source","result":"answer"}}}}
  let program = parsed(source, format=Json)
  let out = @encode.writer(10000, 1000, 64)
  assert_true(emit_source_free_unit_program(program, out))
  assert_eq(
    @encode.finish(out),
    "{\"id\":\"source\",\"inputs\":{},\"results\":{\"answer\":{\"from\":\"rows\"}},\"steps\":[{\"as\":\"rows\",\"values\":{\"rows\":[{\"id\":1,\"meta\":{\"business\":true}}]}}],\"version\":\"actql/0.1\"}",
  )
}

///|
test "source-free unit extraction refuses declarations and other stages" {
  let parameterized = parsed(
    "{\"version\":\"actql/0.1\",\"id\":\"outer\",\"params\":{\"n\":{\"type\":\"number\"}},\"stages\":[{\"id\":\"source\",\"inputs\":{},\"steps\":[],\"results\":{\"rows\":{\"from\":\"rows\"}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}}}}",
    format=Json,
  )
  let out = @encode.writer(10000, 1000, 64)
  assert_false(emit_source_free_unit_program(parameterized, out))
  let staged = parsed(source())
  let other = @encode.writer(10000, 1000, 64)
  assert_false(emit_source_free_unit_program(staged, other))
}

///|
test "opaque binding inventory exposes names without invocation values" {
  let without = parsed(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{},"steps":[{"values":{"rows":[{"id":1}]},"as":"rows"}],"results":{"rows":{"from":"rows"}}}],"results":{"answer":{"from":{"stage":"s","result":"rows"}}}}
    ),
    format=Json,
  )
  assert_eq(program_binding_names(without), [])
  let declared = parsed(
    (
      #|{"version":"actql/0.1","id":"p","bindings":{"target_file":{"type":"resource_ref","resource_kind":"example.file"}},"stages":[{"id":"s","inputs":{},"steps":[{"values":{"rows":[{"id":1}]},"as":"rows"}],"results":{"rows":{"from":"rows"}}}],"results":{"answer":{"from":{"stage":"s","result":"rows"}}}}
    ),
    format=Json,
  )
  assert_eq(program_binding_names(declared), ["target_file"])
}
