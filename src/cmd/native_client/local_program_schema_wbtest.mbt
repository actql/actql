///|
test "Program schema discovery does not acquire a project or physical Host" {
  let pending : Ref[String?] = Ref(None)
  let parsed = command().parse(
    argv=["--config-root", "/not-an-existing-project", "schema"],
    env=Map([]),
  )
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
  execute_and_write_native_reply(parsed, pending)
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
  guard pending.val is Some(wire) else {
    fail("schema discovery must retain its original output for main")
  }
  guard @json.parse(wire) is Object(fields) else {
    fail("the Program schema must remain a JSON object")
  }
  assert_eq(
    fields.get("$id"),
    Some(Json::string("https://smooth.dev/schemas/actql/0.1.json")),
  )
  assert_true(fields.contains("$defs"))
  assert_true(fields.contains("properties"))
  assert_true(@utf8.encode(wire).length() <= 1048576)
}

///|
test "Schema discovery rejects extra operands through the existing parser" {
  let rejected = try {
    ignore(command().parse(argv=["schema", "unexpected"], env=Map([])))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(command_preparation_invocation.val is None)
  assert_true(initial_crypto_invocation.val is None)
}
