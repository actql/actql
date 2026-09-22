///|
/// One exact non-Relation edge inside a checked sequence. Positions are
/// operation-local input positions; repeated uses remain distinct entries.
struct CarrierHandoff {
  producer_step : Int
  consumer_step : Int
  input : Int
  carrier : @carrier.Carrier
}

///|
/// Immutable typed inventory for physical task segmentation. It is not a
/// completion, execution authority, or permission to publish a Carrier.
struct CarrierHandoffIndex {
  sequence : PreparedSequence
  entries : Array[CarrierHandoff]
}

///|
pub(all) enum CarrierHandoffIssue {
  InvalidCarrierHandoffLimits
  CarrierHandoffWorkLimit
  CarrierHandoffEdgeLimit
  InvalidCarrierHandoff(Int, Int)
} derive(Eq, Debug)

///|
pub fn prepare_carrier_handoffs(
  sequence : PreparedSequence,
  max_edges : Int,
  max_work : Int,
) -> Result[CarrierHandoffIndex, CarrierHandoffIssue] {
  if max_edges < 0 || max_work < 0 {
    return Err(InvalidCarrierHandoffLimits)
  }
  let prepared = bound_preparation(sequence_owner(sequence))
  let entries : Array[CarrierHandoff] = []
  let mut work = max_work
  for consumer in 0..<sequence_count(sequence) {
    if work == 0 {
      return Err(CarrierHandoffWorkLimit)
    }
    work -= 1
    guard node_at(prepared, consumer) is Some(node) else {
      return Err(InvalidCarrierHandoff(consumer, -1))
    }
    for input in 0..<node_input_count(node) {
      if work == 0 {
        return Err(CarrierHandoffWorkLimit)
      }
      work -= 1
      match node_input_target(node, input) {
        Some(@pipeline.Step(producer)) => {
          guard producer >= 0 &&
            producer < consumer &&
            preparation_carrier_at(prepared, @pipeline.Step(producer))
            is Some(carrier) else {
            return Err(InvalidCarrierHandoff(consumer, input))
          }
          if @carrier.kind(carrier) != @carrier.RelationKind {
            if entries.length() == max_edges {
              return Err(CarrierHandoffEdgeLimit)
            }
            entries.push({
              producer_step: producer,
              consumer_step: consumer,
              input,
              carrier,
            })
          }
        }
        Some(@pipeline.Input(_)) => ()
        None => return Err(InvalidCarrierHandoff(consumer, input))
      }
    }
  }
  Ok({ sequence, entries, })
}

///|
pub fn carrier_handoff_sequence(
  index : CarrierHandoffIndex,
) -> PreparedSequence {
  index.sequence
}

///|
pub fn carrier_handoff_count(index : CarrierHandoffIndex) -> Int {
  index.entries.length()
}

///|
pub fn carrier_handoff_at(
  index : CarrierHandoffIndex,
  position : Int,
) -> CarrierHandoff? {
  index.entries.get(position)
}

///|
pub fn carrier_handoff_producer(value : CarrierHandoff) -> Int {
  value.producer_step
}

///|
pub fn carrier_handoff_consumer(value : CarrierHandoff) -> Int {
  value.consumer_step
}

///|
pub fn carrier_handoff_input(value : CarrierHandoff) -> Int {
  value.input
}

///|
pub fn carrier_handoff_carrier(value : CarrierHandoff) -> @carrier.Carrier {
  value.carrier
}
