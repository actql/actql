///|
// Actual private controller with explicit read/current ports. This is neither
// an Account grant nor a real Store/VM/Host or installed performance result.
test "saved payload access frame observes originals at boundaries and current at every nested decision" {
  let full = Ref(0)
  let current = Ref(0)
  let reads = Ref(0)
  let result = sdk_payload_read_current_frame(
    () => {
      full.val += 1
      Ok(())
    },
    () => {
      current.val += 1
      Ok(())
    },
    check => {
      for _ in 0..<2 {
        match check() {
          Err(code) => return Err(code)
          Ok(_) => ()
        }
        reads.val += 1
        match check() {
          Err(code) => return Err(code)
          Ok(_) => ()
        }
      }
      Ok(())
    },
  )
  assert_eq(result, Ok(()))
  assert_eq(reads.val, 2)
  assert_eq(full.val, 2)
  assert_eq(current.val, 4)
}

///|
test "saved payload access frame refuses initial originals before any nested read" {
  let reads = Ref(0)
  let checks = Ref(0)
  let result = sdk_payload_read_current_frame(
    () => Err(-41),
    () => {
      checks.val += 1
      Ok(())
    },
    _ => {
      reads.val += 1
      Ok(())
    },
  )
  assert_eq(result, Err(-41))
  assert_eq(reads.val, 0)
  assert_eq(checks.val, 0)
}

///|
test "saved payload access frame retains current revocation and stops further reads" {
  let full = Ref(0)
  let checks = Ref(0)
  let reads = Ref(0)
  let result = sdk_payload_read_current_frame(
    () => {
      full.val += 1
      Ok(())
    },
    () => {
      checks.val += 1
      if checks.val == 2 {
        Err(-35)
      } else {
        Ok(())
      }
    },
    check => {
      for _ in 0..<3 {
        match check() {
          Err(code) => return Err(code)
          Ok(_) => ()
        }
        reads.val += 1
      }
      Ok(())
    },
  )
  assert_eq(result, Err(-35))
  assert_eq(full.val, 1)
  assert_eq(checks.val, 2)
  assert_eq(reads.val, 1)
}

///|
test "saved payload access frame preserves the original read failure without replacement or retry" {
  let full = Ref(0)
  let reads = Ref(0)
  let result = sdk_payload_read_current_frame(
    () => {
      full.val += 1
      if full.val > 1 {
        Err(-9)
      } else {
        Ok(())
      }
    },
    () => Ok(()),
    _ => {
      reads.val += 1
      Err(-17)
    },
  )
  assert_eq(result, Err(-17))
  assert_eq(reads.val, 1)
  assert_eq(full.val, 1)
}

///|
test "saved payload access frame rejects changed final originals before encoder advancement" {
  let unchanged = Ref(true)
  let full = Ref(0)
  let checks = Ref(0)
  let advanced = Ref(false)
  let result = sdk_payload_read_current_frame(
    () => {
      full.val += 1
      if unchanged.val {
        Ok(())
      } else {
        Err(-32)
      }
    },
    () => {
      checks.val += 1
      Ok(())
    },
    check => {
      match check() {
        Err(code) => return Err(code)
        Ok(_) => ()
      }
      unchanged.val = false
      Ok(())
    },
  )
  if result is Ok(_) {
    advanced.val = true
  }
  assert_eq(result, Err(-32))
  assert_eq(full.val, 2)
  assert_eq(checks.val, 1)
  assert_true(!advanced.val)
}

///|
// A final refusal alone cannot erase a metadata read already issued after an
// original changed. Both called controllers are the actual private product
// functions; read/current remain explicit DATA ports, not a real Account/Store.
test "saved payload row fence refuses the next dependent read after original mutation" {
  let unchanged = Ref(true)
  let reads = Ref(0)
  let row : @host.ClientJournalPhysicalRow = {
    key: "same-original-key",
    revision: 0L,
    body: b"original",
  }
  let original = () => if unchanged.val { Ok(()) } else { Err(-32) }
  let read = () => {
    sdk_payload_read_original_row(original, () => {
      reads.val += 1
      Ok(Some(row))
    })
  }
  let result = sdk_payload_read_current_frame(
    original,
    () => Ok(()),
    current => {
      current().unwrap()
      read().unwrap() |> ignore
      unchanged.val = false
      current().unwrap()
      match read() {
        Err(code) => Err(code)
        Ok(_) => Ok(())
      }
    },
  )
  assert_eq(result, Err(-32))
  assert_eq(reads.val, 1)
}
