///|
fn local_traversal_capacity_fixture(
  environment : @environment.WireEnvironment,
  operation_name? : String = "traverse",
  step? : Int = 3,
  proofs? : Array[@wire.ProgramProofClaim] = [],
) -> @host.HostSources raise @encode.EncodeFailure {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let wires = proofs.map(p => @wire.program_proof_witness(p))
  let limits : Array[(Bytes, String)] = []
  for
    (field, unit, suffix) in [
      ("max_graph_paths", "paths", ":paths"),
      ("max_graph_output_rows", "rows", ""),
    ] {
    let ceiling = @policy.ceiling(policy, field).unwrap()
    let host = @host.create(ceiling, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    let out = @encode.writer(10000, 1000, 30)
    @host.emit(host, out)
    let text = @encode.finish(out)
    wires.push(
      @wire.admit(@utf8.encode(text), @host.cid(host), {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 30,
      }).unwrap(),
    )
    let candidates = [wires[wires.length() - 1]]
    let mut maximum = @policy.ceiling_value(ceiling)
    if unit == "rows" && !proofs.is_empty() {
      let candidate = @wire.program_proof_witness(proofs[proofs.length() - 1])
      candidates.push(candidate)
      maximum = maximum.min(@wire.value(candidate))
    }
    candidates.sort_by((a, b) => @wire.cid(a).compare(@wire.cid(b)))
    let texts : Array[String] = []
    for candidate in candidates {
      let writer = @encode.writer(20000, 1000, 30)
      @wire.emit(candidate, writer)
      texts.push(@encode.finish(writer))
    }
    let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
      texts.join(",") +
      "],\"effective_max\":" +
      maximum.to_string() +
      ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"" +
      operation_name +
      ":checked-step:" +
      step.to_string() +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @sha.hex(@utf8.encode(body))
    limits.push(
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
  let mixed = @wire.check_mixed_claims(wires, limits, {
    max_entities: 20,
    max_references: 100,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, proofs, {
    max_witnesses: 20,
    max_references: 100,
  }).unwrap()
  @host.bind_claim_sources(claims, [policy], {
    max_entries: 30,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
}
