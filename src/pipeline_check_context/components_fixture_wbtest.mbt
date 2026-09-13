///|
// Integrity-valid fixture material; expected ownership and limit scopes are fixed by the test.
fn components_fixture_proof(
  law : String,
  value : Int64,
  derivation : String,
  reference? : String = "checked-step:0",
  unit? : String = "rows",
  inputs? : Array[String] = [],
) -> @wire.ProgramProofClaim {
  let body = "{\"inputs\":" +
    components_fixture_cids(inputs) +
    ",\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"" +
    reference +
    "\",\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let id = "sha256:" + @fixture_sha.hex(@wire_utf8.encode(body))
  let dependencies = inputs.copy()
  dependencies.push(id)
  let preimage = "{\"dependencies\":" +
    components_fixture_cids(dependencies, unique=true) +
    ",\"derivation\":" +
    derivation +
    ",\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    id +
    "\",\"semantic_ref\":\"" +
    reference +
    "\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @fixture_sha.hex(@wire_utf8.encode(preimage + "}"))
  let bytes = @wire_utf8.encode(preimage + ",\"witness_cid\":\"" + cid + "\"}")
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let wire = @wire.admit(bytes, cid, caps).unwrap()
  @wire.bind_program_proof(@wire_utf8.encode(body), wire, caps).unwrap()
}

///|
fn components_fixture_cids(
  ids : Array[String],
  unique? : Bool = false,
) -> String {
  let ordered : Array[String] = []
  for id in ids {
    if unique && ordered.contains(id) {
      continue
    }
    ordered.push(id)
    let mut i = ordered.length() - 1
    while i > 0 && ordered[i] < ordered[i - 1] {
      let previous = ordered[i - 1]
      ordered[i - 1] = ordered[i]
      ordered[i] = previous
      i = i - 1
    }
  }
  "[" + ordered.map(id => "\"" + id + "\"").join(",") + "]"
}
