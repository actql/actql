///|
test "typed and unmarked Graph FROM retain authored aliases for static checking" {
  for
    source in [
      "FROM GRAPH g AS row_alias |> MATCH WALK (a) |> SELECT a.id", "FROM GRAPH g row_alias |> MATCH WALK (a) |> SELECT a.id",
      "FROM g AS row_alias |> MATCH WALK (a) |> SELECT a.id", "FROM g row_alias |> MATCH WALK (a) |> SELECT a.id",
    ] {
    let parsed = parse_query_script(source, query_limits()).unwrap()
    assert_eq(
      relation_alias(script_query(parsed)),
      Some({ value: "row_alias", quoted: false, }),
    )
  }
}
