///|
// The preimage and identities below were independently derived from the fixed
// input Catalog and existing normative policy contract, not product output.
test "Effect-free original policy closure retains exact checked and Catalog identities" {
  let prepared = multi_source_prepared(multi_source_program)
  let bodies = prepared_client_publication_policy_bodies(
    prepared, 65536, 8192, 64,
  ).unwrap()
  let identities = bodies.map(body => body.1)
  identities.sort()
  let expected = [
    "sha256:bfb29a3ad6c5f1f3e72e2a59b17ee8df772f88fa8b37ee0f958d6b07cb20c670", "sha256:3cb8e71bd9a1e3a94be47534bd54e21c0e9367b2b5cfa6acd1022a131b12aecc",
    "sha256:63add453865c70e632fc7d5c48708701382e3618db01480fa07967730abf5043", "sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786",
    "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf", "sha256:3e9acc1b4279fc56faba3fd1fd060d15305bb0c2f3e4e1bd2de827e4991e6246",
    "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3",
  ]
  expected.sort()
  assert_eq(identities, expected)
  let root = bodies
    .iter()
    .find_first(body => {
      body.1 ==
      "sha256:bfb29a3ad6c5f1f3e72e2a59b17ee8df772f88fa8b37ee0f958d6b07cb20c670"
    })
    .unwrap()
  assert_eq(
    root.2,
    "{\"classification\":\"unknown\",\"source_data_policy_cids\":[\"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786\",\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\"],\"source_response_policy_cids\":[\"sha256:3cb8e71bd9a1e3a94be47534bd54e21c0e9367b2b5cfa6acd1022a131b12aecc\",\"sha256:63add453865c70e632fc7d5c48708701382e3618db01480fa07967730abf5043\"],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
  )
  let admitted = bodies.map(body => {
    @publication.admit_captured_effect_dependency_body(
      body.0,
      Some(body.1),
      body.2,
      65536,
      8192,
      64,
    ).unwrap()
  })
  let original = admitted
    .iter()
    .find_first(body => {
      @publication.captured_effect_dependency_body_cid(body) == root.1
    })
    .unwrap()
  assert_true(
    @publication.validate_captured_effect_dependency_bodies(
      admitted,
      [original],
      0,
      {
        max_entries: 16,
        max_total_bytes: 65536,
        max_depth: 8,
        max_references: 64,
      },
    )
    is Ok(_),
  )
}

///|
test "Effect-free original policy closure refuses partial coverage and insufficient budget" {
  let partial = multi_source_prepared(
    multi_source_program.replace(
      old="\"joined\":{\"from\":{\"result\":\"rows\",\"stage\":\"join_sources\"}}",
      new="\"joined\":{\"from\":{\"result\":\"rows\",\"stage\":\"acquire_left\"}}",
    ),
  )
  assert_true(
    prepared_client_publication_policy_bodies(partial, 65536, 8192, 64)
    is Err(@checked.MissingDependency),
  )
  let prepared = multi_source_prepared(multi_source_program)
  assert_true(
    prepared_client_publication_policy_bodies(prepared, 1, 8192, 64) is Err(_),
  )
  assert_true(
    prepared_client_publication_policy_bodies(prepared, 65536, 0, 64)
    is Err(@checked.BudgetExceeded),
  )
}

///|
test "Effect-free original policy closure is unchanged by a public Result alias" {
  let original = prepared_client_publication_policy_bodies(
    multi_source_prepared(multi_source_program),
    65536,
    8192,
    64,
  ).unwrap()
  let renamed = multi_source_prepared(
    multi_source_program.replace(
      old="\"joined\":{\"from\":{\"result\":\"rows\",\"stage\":\"join_sources\"}}",
      new="\"renamed\":{\"from\":{\"result\":\"rows\",\"stage\":\"join_sources\"}}",
    ),
  )
  assert_eq(
    prepared_client_publication_policy_bodies(renamed, 65536, 8192, 64).unwrap(),
    original,
  )
}

///|
test "checked policy body construction yields exact original dimensions before output and preserves refusal" {
  let prepared = multi_source_prepared(multi_source_program)
  let observed : Array[(Int, Int, Int)] = []
  let bodies = prepared_client_publication_policy_bodies(
    prepared,
    65536,
    8192,
    64,
    before_body=Some((bytes, nodes, depth) => {
      observed.push((bytes, nodes, depth))
      true
    }),
  ).unwrap()
  // One original combined policy and its two Source response policies emit;
  // the four Catalog bodies borrow existing originals rather than emit again.
  assert_eq(observed.length(), 3)
  assert_eq(observed[0].1, 10)
  assert_eq(observed[0].2, 2)
  let root = bodies[0]
  assert_eq(
    root.1,
    "sha256:bfb29a3ad6c5f1f3e72e2a59b17ee8df772f88fa8b37ee0f958d6b07cb20c670",
  )
  assert_eq(observed[0].0, @utf8.encode(root.2).length())
  let calls = Ref(0)
  assert_true(
    prepared_client_publication_policy_bodies(
      prepared,
      65536,
      8192,
      64,
      before_body=Some((_, _, _) => {
        calls.val += 1
        false
      }),
    )
    is Err(@checked.BudgetExceeded),
  )
  assert_eq(calls.val, 1)
  let retained : Map[String, String] = Map([])
  for (kind, cid, wire) in bodies {
    retained[kind + "\u0000" + cid] = wire
  }
  let original = @strategy.graph_program(prepared.graph)
  let selected = prepared_client_publication_data_policy_cid(prepared).unwrap()
  let filtered = checked_client_publication_policy_bodies(
    original,
    selected,
    65536,
    8192,
    64,
    retain_catalog=true,
    retained_body_keys=Some(retained),
    before_body=Some((_, _, _) => {
      calls.val += 1
      false
    }),
  ).unwrap()
  assert_true(filtered.is_empty())
  assert_eq(calls.val, 1)
}
