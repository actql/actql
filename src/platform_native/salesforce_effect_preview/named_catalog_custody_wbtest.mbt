///|
/// Ordering/callback counterexamples only. These do not substitute a Provider,
/// SQLite or cipher execution; the public connection compiles against them.
test "Catalog adoption follows persistence and exact confirmation" {
  let phases : Array[String] = []
  let saved : Result[Int?, String] = native_catalog_persist_and_confirm(
    () => {
      phases.push("persist")
      Ok(())
    },
    () => {
      phases.push("confirm")
      Ok(3)
    },
    () => {
      phases.push("current")
      true
    },
  )
  assert_eq(saved, Ok(Some(3)))
  assert_eq(phases, ["current", "persist", "confirm", "current"])
}

///|
test "Catalog save or readback failure does not adopt unconfirmed evidence" {
  let confirmations = Ref(0)
  let saved : Result[Int?, String] = native_catalog_persist_and_confirm(
    () => Err("OriginalSaveUnconfirmed"),
    () => {
      confirmations.val += 1
      Ok(3)
    },
    () => true,
  )
  assert_eq(saved, Err("OriginalSaveUnconfirmed"))
  assert_eq(confirmations.val, 0)
  let readback : Result[Int?, String] = native_catalog_persist_and_confirm(
    () => Ok(()),
    () => Err("OriginalReadbackUnconfirmed"),
    () => true,
  )
  assert_eq(readback, Err("OriginalReadbackUnconfirmed"))
}

///|
test "Catalog authority changes retain the save but refuse evidence adoption" {
  for answers in [[false, true], [true, false], [false, false]] {
    let current_reads = Ref(0)
    let saves = Ref(0)
    let confirmations = Ref(0)
    let saved : Result[Int?, String] = native_catalog_persist_and_confirm(
      () => {
        saves.val += 1
        Ok(())
      },
      () => {
        confirmations.val += 1
        Ok(3)
      },
      () => {
        let answer = answers[current_reads.val]
        current_reads.val += 1
        answer
      },
    )
    assert_eq(saved, Ok(None))
    assert_eq(saves.val, 1)
    assert_eq(confirmations.val, 1)
    assert_eq(current_reads.val, 2)
  }
}
