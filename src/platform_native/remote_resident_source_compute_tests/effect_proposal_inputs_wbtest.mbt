// The actual Native consumer supplies Provider proposal values through the
// common checked mapping. These tests do not simulate approval or target I/O.

///|
fn retained_effect_proposal_inputs(
  consumer : @resident.ResidentSourceCompute,
  producer : @resident.ResidentSourceCompute,
  inputs : @strategy.CapturedEffectInputs,
  local_result : Int,
  foreign_result : Int,
) -> Unit raise {
  let deliveries = Ref(0)
  let read = (
    owner : @resident.ResidentSourceCompute,
    pins : @strategy.CapturedEffectInputs,
    result : Int,
    bytes : Int,
    receive : (Int, String, String) -> Result[Unit, Unit],
  ) => {
    owner.read_effect_proposals(
      pins,
      0,
      result,
      resident_compute_limits(),
      16,
      10000,
      bytes,
      100,
      20,
      10000,
      receive,
    )
  }
  let receive = (index, selector, changes) => {
    // Independent expected mapping: id=3 selects account 3 and sets Name=3.
    if index != 0 ||
      selector != "3" ||
      changes != "{\"state\":\"present\",\"value\":{\"Name\":3}}" {
      return Err(())
    }
    deliveries.val += 1
    Ok(())
  }
  assert_true(
    read(producer, inputs, local_result, 4096, receive) is Err(Unavailable),
  )
  assert_true(
    read(consumer, inputs, foreign_result, 4096, receive) is Err(ForeignInput),
  )
  assert_true(
    read(consumer, inputs, local_result, 1, receive) is Err(Proposal(_)),
  )
  assert_eq(deliveries.val, 0)
  let held = consumer.usage().held_bytes
  assert_true(held > 0L)
  assert_true(
    read(consumer, inputs, local_result, 4096, (_, _, _) => Err(()))
    is Err(ReceiverRejected),
  )
  assert_eq(consumer.usage().held_bytes, held)
  assert_true(read(consumer, inputs, local_result, 4096, receive) is Ok(1))
  assert_eq(deliveries.val, 1)
  assert_eq(consumer.usage().held_bytes, held)
  // Returning this independent pin during a callback cannot turn partial
  // delivery into a completed proposal batch or revoke another live pin.
  let interrupted = @strategy.pin_captured_effect_sources(
    consumer.effect_run().unwrap(),
    4,
  ).unwrap()
  assert_true(
    read(consumer, interrupted, local_result, 4096, (_, _, _) => {
      if !@strategy.release_captured_effect_inputs(interrupted) {
        return Err(())
      }
      Ok(())
    })
    is Err(Unavailable),
  )
  assert_eq(consumer.usage().held_bytes, held)
  assert_true(read(consumer, inputs, local_result, 4096, receive) is Ok(1))
  assert_eq(deliveries.val, 2)
}
