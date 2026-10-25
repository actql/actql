///|
test "scratch continuation counter advances only finite original retirement" {
  let cursor = local_managed_scratch_retirement()
  let bridges : Array[Ref[Int?]] = []
  let imports : Array[Ref[Int?]] = []
  let reads : Array[Int?] = Array::make(200, Some(1))
  let cids : Array[String?] = Array::make(200, Some("identity"))
  let issuers : Array[Int] = Array::make(200, 1)
  let mut slices = 0
  while cursor.phase != Retired {
    let before = cursor.steps
    advance_local_managed_scratch_retirement(cursor, bridges, imports, reads, cids, issuers) |> ignore
    assert_true(cursor.steps > before && cursor.steps - before <= 64L)
    slices += 1
    assert_true(slices <= 10)
  }
  assert_true(slices > 1)
  assert_true(reads.all(value => value is None))
  assert_true(cids.all(value => value is None))
  assert_true(issuers.is_empty())
  let completed = cursor.steps
  assert_true(advance_local_managed_scratch_retirement(cursor, bridges, imports, reads, cids, issuers))
  assert_eq(cursor.steps, completed)
}
