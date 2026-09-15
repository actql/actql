///|
// Unchecked input material for the known fixture topology. Never derives its
// coordinates or expected acceptance from an already checked Program.
fn public_search_capacity(
  environment : @environment.WireEnvironment,
  step : Int,
) -> @context.StageCapacityInput raise @encode.EncodeFailure {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let host = @host.create(
    @policy.ceiling(policy, "max_relation_output_rows").unwrap(),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, },
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 30)
  @host.emit(host, writer)
  let host_text = @encode.finish(writer)
  let witness = @wire.admit(@utf8.encode(host_text), @host.cid(host), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
    host_text +
    "],\"effective_max\":" +
    "1000" +
    ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"join:checked-step:" +
    step.to_string() +
    ":output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let text = body.replace(
    old="\"subject_ref\":",
    new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
  )
  let witnesses = [witness]
  let mixed = @wire.check_mixed_claims(witnesses, [(@utf8.encode(text), cid)], {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 10,
    max_references: 20,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 10,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  {
    stage: "consumer",
    sources,
    uses: [@context.Join(step~, output=@wire.mixed_limit_at(mixed, 0).unwrap())],
  }
}
