///|
test "Effect context original phase work preserves independently assembled wire" {
  for length in [1, 4096] {
    let rows = "[{\"s\":\"" + String::make(length, 'a') + "\"}]"
    let snapshot = snapshot_admission_finish(
      snapshot_admission_fixture(rows, ["s"], 1),
      1,
    ).unwrap()
    // These are scoped snapshot fixtures, not an admitted public Run chain.
    // The expected context body is assembled independently of its issuer.
    let body = context_test_body()
      .replace(
        old="\"result_artifacts\":{}",
        new="\"result_artifacts\":{\"answer\":" + snapshot.artifact.wire + "}",
      )
      .replace(
        old="\"result_fields\":{}",
        new="\"result_fields\":{\"answer\":[\"s\"]}",
      )
      .replace(
        old="\"result_values\":{}",
        new="\"result_values\":{\"answer\":" + rows + "}",
      )
    let identity = "sha256:" + @sha.text_hex(body).unwrap()
    let expected = body.replace(
      old=",\"effect_dependency_inventory\"",
      new=",\"effect_context_cid\":\"" +
        identity +
        "\",\"effect_dependency_inventory\"",
    )
    let preparation = context_test_start(snapshots=[snapshot])
    // Disjoint incremental work, not elapsed time or function-call counts:
    // body parse/admission/canonical, full hash, dependency parse, emit, other.
    let counts = Array::make(7, 0)
    let mut done = false
    for _ in 0..<100000 {
      let family = match preparation.phase {
        Parse(_, true) => 0
        Decode(_, true) => 1
        Canonical(_, true) => 2
        Hash(_) => 3
        Parse(_, false) | Decode(_, false) | Canonical(_, false) => 4
        Value(_) => 5
        _ => 6
      }
      let (finished, work) = preparation.advance(1).unwrap()
      assert_true(work >= 0 && work <= 1)
      counts[family] += work
      if finished {
        done = true
        break
      }
    }
    assert_true(done)
    // Actual complete material measurement retains canonical children; only
    // the dependency envelope is parsed. The complete identity hash remains.
    assert_eq(counts[0], 0)
    assert_eq(counts[1], 0)
    assert_eq(counts[2], 0)
    assert_true(counts[3] > 0)
    assert_true(counts[4] > 0)
    let peak = preparation.peak
    let value = preparation.finish().unwrap()
    assert_eq(@json.stringify_value(value, 10000, 1000, 16), expected)
    assert_eq(@json.stringify_value(snapshot.rows, 10000, 1000, 16), rows)
    assert_eq(preparation.live, 0)
    assert_true(preparation.inputs is None && preparation.writer is None)
    println(
      "context length=\{length} body_bytes=\{body.length()} work=\{counts} peak=\{peak}",
    )
  }
}
