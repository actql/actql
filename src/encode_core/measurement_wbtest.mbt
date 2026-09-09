///|
fn measurement_fixture(w : Writer) -> Unit raise EncodeFailure {
  begin_object(w)
  key(w, "é😀")
  begin_array(w)
  string_value(w, "e\u0301\r\n\u0000\"\\😀")
  number_value(w, 1.0e-11)
  null_value(w)
  bool_value(w, true)
  end_array(w)
  end_object(w)
}

///|
test "measurement shares exact emitted byte node depth admission" {
  let emitted = writer(10000, 100, 8)
  measurement_fixture(emitted)
  let document = finish_document(emitted)
  let size = document_bytes(document)
  for cap in [size - 1, size, size + 1] {
    for nodes in [1, 5, 6, 100] {
      for depth in [0, 1, 2, 8] {
        let rendered = try {
          let w = writer(cap, nodes, depth)
          measurement_fixture(w)
          Some(document_bytes(finish_document(w)))
        } catch {
          _ => None
        }
        let measured = try {
          let w = measuring_writer(cap, nodes, depth)
          measurement_fixture(w)
          Some(finish_measurement(w))
        } catch {
          _ => None
        }
        assert_eq(measured, rendered)
      }
    }
  }
  let measured = measuring_writer(size, 100, 8)
  emit_document(measured, document)
  assert_eq(finish_measurement(measured), size)
  assert_true(measured.output is MeasureOutput)
}

///|
test "measurement cannot forge encoded text and is single-use" {
  let measured = measuring_writer(16, 10, 4)
  null_value(measured)
  try finish_document(measured) catch {
    InvalidStructure => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  try finish_measurement(measured) catch {
    ClosedWriter => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  let complete = measuring_writer(4, 1, 0)
  null_value(complete)
  assert_eq(finish_measurement(complete), 4)
  try finish_measurement(complete) catch {
    ClosedWriter => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
}

///|
fn measurement_invalid_case(measured : Bool, case_ : Int) -> String {
  try {
    let w = if measured {
      measuring_writer(1000, 100, 8)
    } else {
      writer(1000, 100, 8)
    }
    match case_ {
      0 => ()
      1 => begin_array(w)
      2 => {
        begin_object(w)
        key(w, "missing")
      }
      3 => {
        begin_object(w)
        key(w, "same")
        null_value(w)
        key(w, "same")
      }
      4 => number_value(w, -0.0)
      5 => number_value(w, 0.0 / 0.0)
      6 => number_value(w, 1.0 / 0.0)
      7 => string_value(w, "😀".unsafe_substring(start=0, end=1))
      8 => {
        null_value(w)
        null_value(w)
      }
      _ => {
        begin_array(w)
        end_object(w)
      }
    }
    if measured {
      ignore(finish_measurement(w))
    } else {
      ignore(finish(w))
    }
    "accepted"
  } catch {
    InvalidStructure => "structure"
    InvalidUnicode => "unicode"
    InvalidNumber => "number"
    OutputLimit => "limit"
    ClosedWriter => "closed"
  }
}

///|
test "measurement rejects the same malformed emissions as text output" {
  for case_ = 0; case_ < 10; case_ = case_ + 1 {
    let baseline = measurement_invalid_case(false, case_)
    assert_true(baseline != "accepted")
    assert_eq(measurement_invalid_case(true, case_), baseline)
  }
  let text = writer(4, 1, 0)
  null_value(text)
  try finish_measurement(text) catch {
    InvalidStructure => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  try finish(text) catch {
    ClosedWriter => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
}
