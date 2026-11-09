///|
// Independent machine Program: two checked Source/filter contributors supply
// both a retained original Result and its bounded terminal slice.
let publication_policy_join_program : String =
  #|{"id":"fixture.two-independent-source-prefix-limit","results":{"original":{"from":{"stage":"join_sources","result":"original"}},"answer":{"from":{"stage":"join_sources","result":"limited"}}},"stages":[{"id":"acquire_left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"rows":{"fields":["id","amount"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id = id"},{"as":"captured","select":["id","amount"]}]},{"id":"acquire_right","inputs":{"remote":{"connector":"crm/right","resource":"r"}},"results":{"rows":{"fields":["id","amount"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id = id"},{"as":"captured","select":["id","amount"]}]},{"id":"join_sources","inputs":{"left_rows":{"result":{"result":"rows","stage":"acquire_left"}},"right_rows":{"result":{"result":"rows","stage":"acquire_right"}}},"results":{"original":{"fields":["id","left_amount","right_amount"],"from":"ordered"},"limited":{"fields":["id","left_amount","right_amount"],"from":"limited"}},"steps":[{"from":"left_rows","join":{"kind":"inner","max_output_rows":100,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","left_amount":"left.amount","right_amount":"right.amount"},"with":"right_rows"}},{"as":"ordered","sort":[{"id":"asc"},{"left_amount":"asc"},{"right_amount":"asc"}]},{"as":"limited","take":{"count":1,"offset":0}}]}],"version":"actql/0.1"}

///|
fn publication_policy_join_pair(
  prepared : PreparedClientProgram,
) -> (@checked.PublicationSourcePolicy, @checked.PublicationSourcePolicy) {
  let program = @strategy.graph_program(prepared.graph)
  let mut original = None
  let mut limited = None
  for index in 0..<@checked.unit_publication_count(program, 2).unwrap() {
    let policy = @checked.publication_source_policy(
      @checked.unit_publication_at(program, 2, index).unwrap(),
    ).unwrap()
    if policy.unknown_provenance {
      limited = Some(policy)
    } else {
      original = Some(policy)
    }
  }
  (original.unwrap(), limited.unwrap())
}

///|
test "Result policy join retains the exact conservative two-source policy in either order" {
  let prepared = multi_source_prepared(publication_policy_join_program)
  let (original, limited) = publication_policy_join_pair(prepared)
  // Effective-policy preimages are independently pinned to the fixture Catalog.
  assert_false(original.unknown_provenance)
  assert_true(limited.unknown_provenance)
  assert_eq(
    limited.cid,
    "sha256:bfb29a3ad6c5f1f3e72e2a59b17ee8df772f88fa8b37ee0f958d6b07cb20c670",
  )
  assert_true(
    @checked.effective_policy_occurrence_count(original.effective) >= 2,
  )
  assert_eq(
    original.cid,
    "sha256:77350feb7da26abe377dd9a35859317430c580c696dc3013b53a03d42e556ac5",
  )
  assert_true(
    physical_equal(
      client_publication_unknown_policy_join(original, limited).unwrap(),
      limited,
    ),
  )
  assert_true(
    physical_equal(
      client_publication_unknown_policy_join(limited, original).unwrap(),
      limited,
    ),
  )
  assert_eq(
    prepared_client_publication_data_policy_cid(prepared),
    Some(limited.cid),
  )
  // The selected conservative CID must retain its complete original dependency
  // body closure for the existing invocation/publication consumers too.
  let bodies = prepared_client_publication_policy_bodies(
    prepared, 65536, 8192, 64,
  ).unwrap()
  assert_eq(
    bodies[0].1,
    "sha256:bfb29a3ad6c5f1f3e72e2a59b17ee8df772f88fa8b37ee0f958d6b07cb20c670",
  )
  assert_eq(
    bodies[0].2,
    "{\"classification\":\"unknown\",\"source_data_policy_cids\":[\"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786\",\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\"],\"source_response_policy_cids\":[\"sha256:3cb8e71bd9a1e3a94be47534bd54e21c0e9367b2b5cfa6acd1022a131b12aecc\",\"sha256:63add453865c70e632fc7d5c48708701382e3618db01480fa07967730abf5043\"],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
  )
  assert_eq(bodies.length(), 7)
}

///|
test "Result policy join refuses equal-CID foreign nominal contributors" {
  let (original, limited) = publication_policy_join_pair(
    multi_source_prepared(publication_policy_join_program),
  )
  let (foreign_original, foreign_limited) = publication_policy_join_pair(
    multi_source_prepared(publication_policy_join_program),
  )
  assert_eq(original.cid, foreign_original.cid)
  assert_eq(limited.cid, foreign_limited.cid)
  assert_true(
    client_publication_unknown_policy_join(original, foreign_limited) is None,
  )
  assert_true(
    client_publication_unknown_policy_join(foreign_original, limited) is None,
  )
  assert_true(
    client_publication_unknown_policy_join(limited, foreign_original) is None,
  )
}

///|
test "Result policy join refuses partial and incompatible Source contributor inventories" {
  let prepared = multi_source_prepared(publication_policy_join_program)
  let (original, limited) = publication_policy_join_pair(prepared)
  let program = @strategy.graph_program(prepared.graph)
  let left_only = @checked.publication_source_policy(
    @checked.unit_publication_at(program, 0, 0).unwrap(),
  ).unwrap()
  assert_true(
    @checked.effective_policy_occurrence_count(left_only.effective) <
    @checked.effective_policy_occurrence_count(limited.effective),
  )
  assert_true(
    client_publication_unknown_policy_join(left_only, limited) is None,
  )
  assert_true(
    client_publication_unknown_policy_join(limited, left_only) is None,
  )
  assert_true(
    client_publication_unknown_policy_join(original, original) is None,
  )
  assert_true(client_publication_unknown_policy_join(limited, limited) is None)
}
