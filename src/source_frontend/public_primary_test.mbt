///|
test "new public read-only Source selects main in the existing lowerer" {
  let context = test_context()
  let formats : Array[Format] = [Sql, Text]
  for format in formats {
    let old = lower("SELECT 1 AS id", format, Some(context)).unwrap()
    let public = lower(
      "SELECT 1 AS id",
      format,
      Some(context),
      public_primary=true,
    ).unwrap()
    let old_program = old.program.unwrap()
    let public_program = public.program.unwrap()
    assert_eq(@program.exports(old_program).map(entry => entry.0), ["answer"])
    assert_eq(@program.exports(public_program).map(entry => entry.0), ["main"])
    // This is one actual Program export, not an alias or a duplicate Result.
    assert_eq(@program.export_count(public_program), 1)
    assert_true(old.document != public.document)
    assert_eq(
      lower("SELECT 1 AS id", format, Some(context)).unwrap().document,
      old.document,
    )
  }
}

///|
test "public default never rewrites explicit Result or structured Program bytes" {
  let context = test_context()
  for
    text in [
      "SELECT 1 AS id |> RESULT answer", "SELECT 1 AS id |> RESULT main", "SELECT 1 AS id |> RESULT MiXeD",
      "SELECT 1 AS id |> RESULT saved |> SELECT id",
    ] {
    let original = lower(text, Text, Some(context)).unwrap()
    let public = lower(text, Text, Some(context), public_primary=true).unwrap()
    assert_eq(public.document, original.document)
  }
  let tail = lower(
    "SELECT 1 AS id |> RESULT saved |> SELECT id",
    Text,
    Some(context),
    public_primary=true,
  ).unwrap().program.unwrap()
  let names = @program.exports(tail).map(entry => entry.0)
  assert_eq(names.length(), 2)
  assert_true(names.contains("saved"))
  assert_true(names.contains("answer"))
  let document = lower("SELECT 1 AS id", Sql, Some(context)).unwrap().document
  assert_eq(
    lower(document, Json, Some(context), public_primary=true).unwrap().document,
    document,
  )
  assert_true(
    lower("SELECT 1 AS id", Sql, None, public_primary=true)
    is Err(MissingQueryContext),
  )
}
