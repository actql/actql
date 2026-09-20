///|
// Host-ceiling capacity evidence for the fixed reach conformance fixture.
// Reach does not require an authored proof for either traversal limit.
fn reach_fixture_capacity(
  environment : @environment.WireEnvironment,
  stage : String,
  step? : Int = 1,
) -> @context.StageCapacityInput raise {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let witnesses : Array[@wire.WireWitness] = []
  let artifacts : Array[(Bytes, String)] = []
  for
    (field, unit, suffix) in [
      ("max_graph_paths", "paths", ":paths"),
      ("max_graph_output_rows", "rows", ""),
    ] {
    let host = @host.create(@capacity_policy.ceiling(policy, field).unwrap(), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    let writer = @encode.writer(10000, 1000, 30)
    @host.emit(host, writer)
    let text = @encode.finish(writer)
    let wire = @wire.admit(@utf8.encode(text), @host.cid(host), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    witnesses.push(wire)
    let prefix = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\"," +
      "\"candidates\":[" +
      text +
      "],\"effective_max\":" +
      @wire.value(wire).to_string() +
      ",\"enforcement\":\"engine_atomic\""
    let tail = ",\"subject_ref\":\"reach:checked-step:" +
      step.to_string() +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + tail))
    artifacts.push(
      (
        @utf8.encode(prefix + ",\"resolved_limit_cid\":\"" + cid + "\"" + tail),
        cid,
      ),
    )
  }
  let mixed = @wire.check_mixed_claims(witnesses, artifacts, {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 20,
    max_references: 100,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 20,
    max_bytes: 20000,
    max_nodes: 2000,
    max_depth: 30,
  }).unwrap()
  {
    stage,
    sources,
    uses: [
      @context.Traversal(
        step~,
        paths=@wire.mixed_limit_at(mixed, 0).unwrap(),
        output=@wire.mixed_limit_at(mixed, 1).unwrap(),
      ),
    ],
  }
}
