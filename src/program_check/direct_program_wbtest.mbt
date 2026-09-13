///|
test "direct SourceView reaches the final source execution audit from authored source" {
  let text =
    #|{"version":"actql/0.1","id":"direct","stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"id":1,"tenant":null}}},"steps":[{"distinct":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let program = @syntax.parse(
    text,
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
  let environment = remote_environment_fixture()
  // No Program arithmetic assertion is needed: publication retains the Host
  // bound and distinct establishes its own key. Actual acquisition is not run.
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  try
    check(
      program,
      environment,
      None,
      [[@context.CapacityMaterial::{ sources, consumers: [], }]],
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      source_limits_fixture(1),
      max_work=100000000,
      max_bytes=10000000,
      max_nodes=1000000,
      max_depth=100,
    )
  catch {
    Units(UnclosedSourceExecution(0, 0)) => ()
    error => raise error
  } noraise {
    _ => fail("unclosed source execution escaped")
  }
}
