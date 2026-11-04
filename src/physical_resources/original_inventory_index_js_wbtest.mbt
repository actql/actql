///|
// Observe actual old slot/order array reads inside this SAME Core-created
// inventory. The private test proxy changes no token/element/owner identity.
// New indexed storage may remove the old slots field; only those old-family
// probes are counted, not Map internals, total instructions, CPU or latency.
extern "js" fn observe_original_slot_probes(
  original : OriginalTokenSlots[Reservation],
) -> () -> Int =
  #|original => {
  #|  let reads = 0;
  #|  for (const name of ['slots', 'order']) {
  #|    const array = original[name];
  #|    if (!Array.isArray(array)) continue;
  #|    original[name] = new Proxy(array, {
  #|      get(target,key,receiver) {
  #|        if (typeof key === 'string' && /^(0|[1-9][0-9]*)$/.test(key)) reads++;
  #|        return Reflect.get(target,key,receiver);
  #|      }
  #|    });
  #|  }
  #|  return () => reads;
  #|}

///|
fn indexed_inventory_test_ledger(size : Int) -> (Ledger, CapacityReservation) {
  let ledger = create_ledger({
    planning_work: 1000,
    attempts: size,
    holdings: size,
    transfer_bytes: 0L,
    retained_bytes: 1000000L,
    execution_bytes: 1000000L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 10000L, 10000L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, size, size, size).unwrap()
  |> ignore
  (ledger, bootstrap)
}

///|
test "original census append never scans its already occupied token prefix" {
  let count = 64
  let (ledger, _) = indexed_inventory_test_ledger(count)
  let inventory = ledger.original_inventory.unwrap()
  let probes = observe_original_slot_probes(inventory.reservations)
  let originals = Array::makei(count, _ => {
    reserve_capacity(ledger, 1L, 1L).unwrap()
  })
  let observed = probes()
  assert_true(observed <= 4 * count, msg="occupied-prefix probes=\{observed}")
  assert_eq(inventory.reservations.length(), count)
  for index in 0..<count {
    assert_true(
      physical_equal(
        inventory.reservations[index],
        originals[index].reservation,
      ),
    )
  }
}

///|
test "original census forward and reverse retirement do not rescan or shift the remaining token inventory" {
  let count = 64
  for reverse in [false, true] {
    let (ledger, _) = indexed_inventory_test_ledger(count)
    let inventory = ledger.original_inventory.unwrap()
    let originals = Array::makei(count, _ => {
      reserve_capacity(ledger, 1L, 1L).unwrap()
    })
    let probes = observe_original_slot_probes(inventory.reservations)
    for step in 0..<count {
      let index = if reverse { count - step - 1 } else { step }
      settle_reservation(ledger, originals[index].reservation).unwrap()
    }
    let observed = probes()
    assert_true(observed <= 4 * count, msg="retirement probes=\{observed}")
    assert_true(inventory.reservations.is_empty())
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10000L)
    assert_eq(ledger_usage(ledger).reserved_execution_bytes, 10000L)
    assert_eq(ledger_usage(ledger).attempts, 0)
  }
}

///|
// Re-evaluate the ACTUAL compiled private hash, not a handwritten surrogate,
// in two independent closures with different module seed bindings. No Ledger,
// token, authority or physical object is constructed or remapped here.
extern "js" fn original_serial_hash_cross_module_scalar(
  key : OriginalTokenSerial,
  hash : (OriginalTokenSerial) -> Int,
  expected : Int,
) -> Bool =
  #|(key, hash, expected) => {
  #|  if (typeof key !== 'number') return false;
  #|  const source = Function.prototype.toString.call(hash);
  #|  const first = new Function('seed', 'return (' + source + ')')(17);
  #|  const second = new Function('seed', 'return (' + source + ')')(987654321);
  #|  return first(key) === expected && second(key) === expected;
  #|}

///|
test "original serial key keeps scalar backing and the same hash across module seed closures" {
  for serial in [-2147483648, -2, -1, 0, 1, 2147483647] {
    assert_true(
      original_serial_hash_cross_module_scalar(
        OriginalTokenSerial(serial),
        Hash::hash,
        serial,
      ),
    )
  }
}
