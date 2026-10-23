///|
fn aoa_emission_fixture() -> String {
  "{\"output\":\"values_0\",\"sources\":{},\"steps\":[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1},{\"id\":2}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}}],\"version\":\"aoa-pipeline/0.1\"}"
}

///|
fn previous_aoa_identity_emission(
  wire : String,
  body : @canonical.CanonicalValue,
  bytes : Int,
  nodes : Int,
  depth : Int,
  emit? : (@canonical.CanonicalValue, @encode.Writer) -> Unit raise @encode.EncodeFailure = @canonical.emit_value,
) -> Result[ClientValuesAoAIdentity, ClientValuesAoAIdentityIssue] {
  try {
    let text = @encode.writer(bytes, nodes, depth)
    emit(body, text)
    if @encode.finish(text) != wire {
      return Err(NoncanonicalPipeline)
    }
    let hash = @encode.hashing_writer(bytes, nodes, depth)
    emit(body, hash)
    Ok({ wire, cid: "sha256:" + @encode.finish_hash(hash), })
  } catch {
    _ => Err(Encoding)
  }
}

///|
test "Values AoA canonical comparison and identity emit the same tree once" {
  let wire = aoa_emission_fixture()
  let body = parse_plan_identity_value(wire, 10000, 1000, 20).unwrap()
  let calls = Ref(0)
  let emit = (value, writer) => {
    calls.val += 1
    @canonical.emit_value(value, writer)
  }
  let prior = previous_aoa_identity_emission(wire, body, 10000, 1000, 20, emit~).unwrap()
  assert_eq(calls.val, 2)
  calls.val = 0
  let current = finish_client_values_aoa_identity(
    wire,
    body,
    10000,
    1000,
    20,
    emit~,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(current.wire, wire)
  assert_eq(current.wire, prior.wire)
  assert_eq(current.cid, prior.cid)
  assert_eq(
    current.cid,
    "sha256:5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723",
  )
}

///|
test "Values AoA single emission retains prior exact bounds and mismatch refusals" {
  for
    wire in [
      aoa_emission_fixture(),
      "{\"é😀\":[1,null,{\"text\":\"é😀\"}]}",
    ] {
    let body = parse_plan_identity_value(wire, 10000, 1000, 20).unwrap()
    let measure = @encode.hashing_writer(10000, 1000, 20)
    @canonical.emit_value(body, measure)
    let (_, bytes, nodes, depth) = @encode.finish_hash_metrics(measure)
    let current = finish_client_values_aoa_identity(
      wire, body, bytes, nodes, depth,
    ).unwrap()
    let prior = previous_aoa_identity_emission(wire, body, bytes, nodes, depth).unwrap()
    assert_eq(current.wire, prior.wire)
    assert_eq(current.cid, prior.cid)
    for
      (b, n, d) in [
        (bytes - 1, nodes, depth),
        (bytes, nodes - 1, depth),
        (bytes, nodes, depth - 1),
        (-1, nodes, depth),
        (bytes, 0, depth),
      ] {
      assert_true(
        finish_client_values_aoa_identity(wire, body, b, n, d) is Err(Encoding),
      )
      assert_true(
        previous_aoa_identity_emission(wire, body, b, n, d) is Err(Encoding),
      )
    }
    assert_true(
      finish_client_values_aoa_identity(" " + wire, body, 10000, 1000, 20)
      is Err(NoncanonicalPipeline),
    )
    assert_true(
      previous_aoa_identity_emission(" " + wire, body, 10000, 1000, 20)
      is Err(NoncanonicalPipeline),
    )
  }
}

///|
test "Values AoA interrupted emission exposes no completed identity" {
  let wire = aoa_emission_fixture()
  let body = parse_plan_identity_value(wire, 10000, 1000, 20).unwrap()
  assert_true(
    finish_client_values_aoa_identity(wire, body, 10000, 1000, 20, emit=(
      _,
      writer,
    ) => {
      @encode.begin_object(writer)
      @encode.key(writer, "partial")
      raise @encode.InvalidStructure
    })
    is Err(Encoding),
  )
}
