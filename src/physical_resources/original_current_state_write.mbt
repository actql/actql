///|
// A cursor on the existing parked census, not a descriptor/read/restore issuer.
// The original Run funds this control, Writer/backing, per-block frames and
// Store/hash overlap before use. No numerical physical profile is adopted.
struct OriginalCurrentStateWrite[T] {
  mut park : OriginalResourcePark[T]?
  mut writer : @encode.Writer?
  total : Int
  mut position : Int
}

///|
// Borrow the SAME cursor only while it belongs to the exact current park.
// This is not Writer output completion, Store ACK or journal authority.
pub fn[T] original_current_state_write_current(
  value : OriginalCurrentStateWrite[T],
  park : OriginalResourcePark[T],
) -> OriginalCurrentStateWrite[T]? {
  guard value.park is Some(original) &&
    physical_equal(original, park) &&
    value.writer is Some(_) &&
    park.origin is Some(origin) &&
    original_resource_park_current(park, origin) is Some(_) else {
    return None
  }
  Some(value)
}

///|
// The dedicated Writer remains the caller's physical cleanup responsibility.
// Exact currentness and one prepaid codec operation are checked before this
// cursor allocates. A normal park has no prepaid operation and is refused.
pub fn[T] start_original_current_state_write(
  park : OriginalResourcePark[T],
  origin : T,
  writer : @encode.Writer,
) -> Result[OriginalCurrentStateWrite[T], OriginalStateWriteIssue] {
  guard original_resource_park_current(park, origin) is Some(_) else {
    return Err(Original(ChangedOriginalState))
  }
  guard park.state_write_work is Some(total) else {
    return Err(Original(SpentClaim))
  }
  park.state_write_work = None
  Ok({ park: Some(park), writer: Some(writer), total, position: 0, })
}

///|
fn[T] original_current_state_write_block(
  value : OriginalCurrentStateWrite[T],
  park : OriginalResourcePark[T],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let inventory = park.fence.unwrap().identity.ledger.original_inventory.unwrap()
  let ledger = inventory.identity.ledger
  let n = inventory.reservations.length()
  let h = inventory.holdings.length()
  let d = inventory.delegations.length()
  let step = value.position
  match step {
    0 => {
      @encode.begin_array(writer)
      @encode.string_value(writer, "actql-original-ledger-state/0.1")
    }
    1 => state_write_limits(writer, ledger.limits)
    2 => state_write_usage(writer, ledger.usage)
    3 => {
      @encode.begin_array(writer)
      state_write_int(writer, ledger.delegated_planning)
      state_write_int(writer, ledger.delegated_attempts)
      state_write_int(writer, ledger.delegated_holdings)
      @encode.end_array(writer)
    }
    4 => state_write_optional_quantities(writer, ledger.quantity_limits)
    5 => {
      @encode.begin_array(writer)
      state_write_quantities(writer, ledger.quantity_usage.reserved)
      state_write_quantities(writer, ledger.quantity_usage.uncertain)
      state_write_quantities(writer, ledger.quantity_usage.consumed)
      @encode.end_array(writer)
    }
    6 => {
      @encode.begin_array(writer)
      state_write_optional_int(writer, ledger.next_capacity_serial)
      state_write_optional_int(writer, ledger.next_attempt_serial)
      state_write_optional_int(writer, ledger.next_holding_serial)
      @encode.end_array(writer)
    }
    7 => {
      @encode.begin_array(writer)
      state_write_int(writer, inventory.max_reservations)
      state_write_int(writer, inventory.max_holdings)
      state_write_int(writer, inventory.max_delegations)
      @encode.bool_value(writer, inventory.descriptor_issued)
      @encode.bool_value(writer, inventory.read_claimed)
      @encode.bool_value(writer, inventory.closing)
      @encode.string_value(
        writer,
        if park.previous is Some(ConsumerStopping(_)) {
          "stopping"
        } else {
          "parked"
        },
      )
      @encode.bool_value(writer, true)
      @encode.end_array(writer)
    }
    8 =>
      state_write_reservation(
        writer,
        original_reservation_snapshot(inventory.bootstrap.reservation),
      )
    9 => @encode.begin_array(writer)
    _ =>
      if step < 10 + n {
        state_write_reservation(
          writer,
          original_reservation_snapshot(inventory.reservations[step - 10]),
        )
      } else if step == 10 + n {
        @encode.end_array(writer)
      } else if step == 11 + n {
        @encode.begin_array(writer)
      } else if step < 12 + n + h {
        let token = inventory.holdings[step - 12 - n]
        @encode.begin_array(writer)
        state_write_int(writer, token.serial)
        state_write_int(writer, token.reservation_serial)
        state_write_long(writer, token.bytes)
        @encode.bool_value(writer, token.live)
        @encode.end_array(writer)
      } else if step == 12 + n + h {
        @encode.end_array(writer)
      } else if step == 13 + n + h {
        @encode.begin_array(writer)
      } else if step < 14 + n + h + d {
        let token = inventory.delegations[step - 14 - n - h]
        @encode.begin_array(writer)
        state_write_int(writer, token.reservation.serial)
        state_write_limits(writer, token.limits)
        @encode.begin_array(writer)
        let (
          planning,
          attempts,
          holdings,
          transfer,
          uncertain,
          pending,
          reservations,
          delegations,
        ) = original_delegation_snapshot(token)
        state_write_int(writer, planning)
        state_write_int(writer, attempts)
        state_write_int(writer, holdings)
        state_write_long(writer, transfer)
        state_write_long(writer, uncertain)
        state_write_int(writer, pending)
        state_write_int(writer, reservations)
        state_write_int(writer, delegations)
        @encode.end_array(writer)
        @encode.end_array(writer)
      } else {
        @encode.end_array(writer)
      }
  }
}

///|
pub fn[T] cancel_original_current_state_write(
  value : OriginalCurrentStateWrite[T],
) -> Unit {
  if value.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  value.writer = None
  value.park = None
  // Preserve the actual park/consumer/census and all spent work. Cancellation
  // of a codec is not journal invalidation, physical cleanup or unpark.
}

///|
pub fn[T] advance_original_current_state_write(
  value : OriginalCurrentStateWrite[T],
  quantum : Int,
) -> OriginalStateWritePoll {
  if quantum <= 0 {
    return StateWriteFailed(InvalidQuantum, work=0)
  }
  guard value.park is Some(park) && value.writer is Some(writer) else {
    return StateWriteFailed(Terminal, work=0)
  }
  guard park.origin is Some(origin) &&
    original_resource_park_current(park, origin) is Some(_) else {
    cancel_original_current_state_write(value)
    return StateWriteFailed(Original(ChangedOriginalState), work=0)
  }
  let mut work = 0
  while work < quantum && value.position < value.total {
    original_current_state_write_block(value, park, writer) catch {
      _ => {
        cancel_original_current_state_write(value)
        return StateWriteFailed(Encoding, work=work + 1)
      }
    }
    value.position += 1
    work += 1
  }
  if value.position == value.total {
    value.writer = None
    value.park = None
    StateWriteComplete(work~)
  } else {
    StateWriteContinue(work~)
  }
}
