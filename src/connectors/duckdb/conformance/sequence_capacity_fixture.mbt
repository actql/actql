///|
fn sequence_fixture_capacity(
  environment : @environment.WireEnvironment,
  stage : String,
  step? : Int = 0,
  input_rows? : Int64 = 40L,
) -> @context.StageCapacityInput raise {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let witnesses = []
  let artifacts = []
  let mut output_host_cid = ""
  for
    (field, unit, suffix) in [
      ("max_temporal_matches_per_key", "matches_per_key", "matches-per-key"),
      ("max_temporal_output_rows", "rows", "output"),
    ] {
    let host = @host.create(@capacity_policy.ceiling(policy, field).unwrap(), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    let writer = @encode.writer(10000, 1000, 30)
    @host.emit(host, writer)
    let host_text = @encode.finish(writer)
    let host_wire = @wire.admit(@utf8.encode(host_text), @host.cid(host), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    witnesses.push(host_wire)
    if suffix == "output" {
      output_host_cid = @wire.cid(host_wire)
    }
    let effective = @wire.value(host_wire)
    let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
      host_text +
      "],\"effective_max\":" +
      effective.to_string() +
      ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"sequence:checked-step:" +
      step.to_string() +
      ":" +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @sha.hex(@utf8.encode(body))
    artifacts.push(
      (
        @utf8.encode(
          body.replace(
            old="\"subject_ref\":",
            new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
          ),
        ),
        cid,
      ),
    )
  }
  let input = traversal_fixture_proof("actql.bound.values", input_rows, step=0)
  let output = traversal_fixture_proof(
    "actql.bound.sequence-output",
    @wire.value(witnesses[1]),
    inputs=[output_host_cid],
    step~,
  )
  witnesses.push(@wire.program_proof_witness(input))
  witnesses.push(@wire.program_proof_witness(output))
  let mixed = @wire.check_mixed_claims(witnesses, artifacts, {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [input, output], {
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
    stage,
    sources,
    uses: [
      Sequence(
        step~,
        matches=@wire.mixed_limit_at(mixed, 0).unwrap(),
        output=@wire.mixed_limit_at(mixed, 1).unwrap(),
      ),
    ],
  }
}
