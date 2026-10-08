///|
fn decode_operational_reference(
  item : @decode.ObjectView,
  expired : Bool,
  off : Bool,
) -> OperationalTimeReference raise PolicyWireStop {
  let position = policy_wire_int(item, "position")
  let task = policy_wire_int(item, "task")
  let quantity = policy_wire_text(item, "quantity")
  if task < 1 ||
    ![
      "task-processing", "task-release", "resident-preparation", "resident-import",
      "run-caller-elapsed",
    ].contains(quantity) {
    raise PolicyWireStop
  }
  let count = policy_wire_int(item, "sample_count")
  if count > 18 {
    raise PolicyWireStop
  }
  let median = estimate_number(item, "median_ms")
  let minimum = estimate_number(item, "minimum_ms")
  let maximum = estimate_number(item, "maximum_ms")
  let status = policy_wire_text(item, "status")
  let reason = policy_wire_text(item, "reason")
  if status == "reference" {
    guard median is Some(mid) &&
      minimum is Some(low) &&
      maximum is Some(high) &&
      count >= 3 &&
      reason == "" &&
      low <= mid &&
      mid <= high else {
      raise PolicyWireStop
    }
  } else if status != "unknown" ||
    ![
      "conditions-mismatch", "physical-phase-observer-off", "freshness-insufficient",
      "samples-insufficient", "candidate-attribution-insufficient", "quantity-unobserved",
    ].contains(reason) ||
    median is Some(_) ||
    minimum is Some(_) ||
    maximum is Some(_) {
    raise PolicyWireStop
  }
  {
    position,
    task,
    quantity,
    median_ms: if expired || off {
      None
    } else {
      median
    },
    minimum_ms: if expired || off {
      None
    } else {
      minimum
    },
    maximum_ms: if expired || off {
      None
    } else {
      maximum
    },
    sample_count: count,
    unknown_reason: if expired {
      Some("freshness-insufficient")
    } else if off {
      Some("physical-phase-observer-off")
    } else if status == "unknown" {
      Some(reason)
    } else {
      None
    },
  }
}
