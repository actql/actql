///|
test "Carrier work exhaustion prevents the next guarded visit" {
  // This checks the actual shared primitive, not a selector-loop position.
  for budget in [0, 4, 5] {
    let work = Ref(budget)
    let observed = Ref(0)
    let observe = fn() { observed.val += 1 }
    let stopped = try {
      for _ in 0..<(budget + 1) {
        carrier_work(work)
        observe()
      }
      false
    } catch {
      CarrierWorkStop => true
    }
    assert_true(stopped)
    assert_eq(observed.val, budget)
    assert_eq(work.val, 0)
    let stopped_again = try {
      carrier_work(work)
      observe()
      false
    } catch {
      CarrierWorkStop => true
    }
    assert_true(stopped_again)
    assert_eq(observed.val, budget)
    assert_eq(work.val, 0)
  }
}

///|
test "Carrier work reservation refuses before the allocation callback" {
  for budget in [0, 4, 5] {
    let work = Ref(budget)
    let allocations = Ref(0)
    let allocate = fn() {
      allocations.val += 1
      Array::make(5, false)
    }
    let admitted = try {
      carrier_work(work, amount=5)
      allocate().length() == 5
    } catch {
      CarrierWorkStop => false
    }
    assert_eq(admitted, budget == 5)
    assert_eq(allocations.val, if budget == 5 { 1 } else { 0 })
    assert_eq(work.val, if budget == 5 { 0 } else { budget })
  }
}
