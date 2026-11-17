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
    // Diagnostic incremental work families, not golden implementation counts.
    // Independent bytes/CID and bounded progress remain the behavioral oracle.
    let counts = Array::make(4, 0)
    let mut done = false
    for _ in 0..<100000 {
      let family = match preparation.phase {
        Hash(_) => 0
        DependencyEntry(_) | DependencyField(_, _) | DependencyValue(_, _) => 1
        Value(_) => 2
        _ => 3
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
    let peak = preparation.peak
    let value = preparation.finish().unwrap()
    assert_eq(@json.stringify_value(value, 10000, 1000, 16), expected)
    assert_eq(@json.stringify_value(snapshot.rows, 10000, 1000, 16), rows)
    assert_eq(preparation.live, 0)
    assert_true(preparation.inputs is None && preparation.writer is None)
    println(
      "context length=\{length} body_bytes=\{body.length()} work=\{@debug.to_string(counts)} peak=\{peak}",
    )
  }
}
