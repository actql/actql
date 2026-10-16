///|
test "unpublished STORE never compiles as its ordinary Relation prefix" {
  // No installed write selection is supplied: parsing is not Effect authority.
  // Both public compile entries must refuse instead of silently dropping STORE.
  for
    source in [
      "SELECT 1 AS id |> EFFECT STORE local.archive", "WITH t AS (SELECT 1 AS id) FROM t |> EFFECT STORE local.archive",
      "SELECT 1 AS id |> EFFECT STORE local.files SET (path = 'x', content = id)",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let context = { ..fixture_context(), inputs: [], }
    assert_true(
      compile(query, context, construction_limits())
      is Err(StoreTargetBinding(UnresolvedTarget)),
    )
    assert_true(
      compile_query_script(
        @query.single_query_script(query),
        context,
        construction_limits(),
      )
      is Err(StoreTargetBinding(UnresolvedTarget)),
    )
  }
}
