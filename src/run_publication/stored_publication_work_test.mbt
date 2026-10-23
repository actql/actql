///|
test "stored publication first validation work is separate from original confirmation" {
  let fixture = commit_read_fixture()
  let rows = stored_publication_test_rows(fixture)
  let counts : Array[Int] = []
  let sizes = fixture.originals.map(contract => {
    @utf8.encode(publication_contract_json(contract)).length()
  })
  for quantum in [1, 256] {
    let mut reads = 0
    let mut bytes = 0
    let owner = stored_publication_test_load(
      fixture,
      cid => {
        let wire = rows.get(cid).unwrap()
        reads += 1
        bytes += @utf8.encode(wire).length()
        Ok(Some(wire))
      },
      () => Ok(()),
    ).unwrap()
    assert_eq(reads, 14)
    let mut expected_bytes = 0
    for size in sizes {
      expected_bytes += size
    }
    assert_eq(bytes, expected_bytes)
    let first = commit_read_complete(owner, quantum)
    assert_true(first > 1)
    counts.push(first)
    let view = owner.finish_view().unwrap()
    for index in 0..<14 {
      assert_eq(
        publication_contract_json(owner.view_contract(view, index).unwrap()),
        publication_contract_json(fixture.originals[index]),
      )
    }
    owner
    .begin_observed_commit(
      view,
      owner.view_contract(view, 5).unwrap(),
      owner.view_contract(view, 6).unwrap(),
      owner.view_contract(view, 7).unwrap(),
    )
    .unwrap()
    let confirmation = observed_commit_test_complete(owner, view, quantum)
    assert_eq(confirmation, 1)
    assert_eq(reads, 14)
    owner.release_observed_commit(view).unwrap()
    owner.release_view(view).unwrap()
    println(
      "stored publication quantum=\{quantum} contract_read_callbacks=\{reads} wire_bytes=\{bytes} contract_bytes=\{sizes} first_validation_work=\{first} confirmation_work=\{confirmation}",
    )
  }
  assert_eq(counts[0], counts[1])
  fixture.preparation.cancel()
}

///|
test "stored publication computation work uses the same admitted cold contracts" {
  let fixture = commit_read_fixture()
  let rows = stored_publication_test_rows(fixture)
  let owner = stored_publication_test_load(fixture, cid => Ok(rows.get(cid)), () => {
    Ok(())
  }).unwrap()
  let whole_work = commit_read_complete(owner, 1)
  let view = owner.finish_view().unwrap()
  let original = (index : Int) => owner.view_contract(view, index).unwrap()
  let computation = start_effect_free_run_evidence_check(
    original(0),
    original(1),
    [original(8)],
    [original(9)],
    original(2),
    original(3),
    original(4),
    65536,
    4096,
    32,
    32756,
  )
  let mut computation_work = 0
  let mut complete = false
  for _ in 0..<500000 {
    let (done, used) = computation.advance(1).unwrap()
    assert_true(used >= 0 && used <= 1)
    computation_work += used
    if done {
      complete = true
      break
    }
  }
  assert_true(complete)
  computation.finish().unwrap()
  assert_true(computation_work > 0 && computation_work < whole_work)
  computation.cancel()
  assert_true(computation.advance(1) is Err(_))
  owner.release_view(view).unwrap()
  fixture.preparation.cancel()
  // The commit owner delegates one computation step per parent step. The
  // subtraction covers its other phases; synchronous admission is not counted.
  println(
    "stored publication whole_work=\{whole_work} computation_work=\{computation_work} other_commit_work=\{whole_work - computation_work}",
  )
}
