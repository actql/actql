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
