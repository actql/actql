///|
test "Local document root is independent of the selected private configuration" {
  let selected = command().parse(
    argv=[
      "--mode", "local", "--config-root", "private-original", "--input-root", ".",
      "connect", "--json",
    ],
    env=Map([]),
  )
  assert_eq(required(selected, "config-root"), "private-original")
  assert_eq(local_document_root(selected, "private-original"), ".")
  let legacy = command().parse(
    argv=[
      "--mode", "local", "--config-root", "private-original", "connect", "--json",
    ],
    env=Map([]),
  )
  assert_eq(local_document_root(legacy, "private-original"), "private-original")
}

///|
test "Local document root cannot silently affect Remote transport" {
  let selected = command().parse(
    argv=["--input-root", "unopened", "connect", "--json"],
    env=Map([]),
  )
  let refusal = try {
    execute(selected) |> ignore
    None
  } catch {
    ClientStop(reason) => Some(reason)
  }
  assert_eq(refusal, Some("Local document root is unavailable in Remote mode"))
}
