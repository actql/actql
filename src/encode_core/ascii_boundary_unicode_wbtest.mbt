///|
fn ascii_boundary_writer(sink : Int, bytes : Int) -> Writer raise EncodeFailure {
  match sink {
    0 => writer(bytes, 4, 2)
    1 => measuring_writer(bytes, 4, 2)
    2 => hashing_writer(bytes, 4, 2)
    3 => buffered_writer(bytes, 4, 2, bytes)
    4 => buffered_hashing_writer(bytes, 4, 2, bytes)
    _ => comparing_writer("", bytes, 4, 2)
  }
}

///|
test "ASCII spans reject following lone surrogates through every sink and cursor" {
  let low = "😀".unsafe_substring(start=1, end=2)
  for length in [1, 63, 64, 65, 255, 256, 257] {
    let text = String::make(length, 'a') + low
    for sink in 0..<6 {
      for lane in 0..<4 {
        let w = ascii_boundary_writer(sink, 1024)
        let rejected = try {
          match lane {
            0 => string_value(w, text)
            1 => {
              begin_object(w)
              key(w, text)
            }
            2 => {
              begin_ordered_object(w)
              ordered_key(w, text)
            }
            _ => {
              let cursor = start_string_value(w, text)
              while !advance_string_value(cursor) {
                ()
              }
            }
          }
          false
        } catch {
          InvalidUnicode => true
          _ => false
        }
        assert_true(rejected)
        assert_encoding_closed(w)
      }
    }
  }
}

///|
test "ASCII span limits precede later Unicode errors without panicking" {
  let low = "😀".unsafe_substring(start=1, end=2)
  for sink in 0..<6 {
    for (bytes, unicode) in [(32, false), (33, true)] {
      let w = ascii_boundary_writer(sink, bytes)
      let rejected = try {
        string_value(w, String::make(32, 'a') + low)
        false
      } catch {
        OutputLimit => !unicode
        InvalidUnicode => unicode
        _ => false
      }
      assert_true(rejected)
      assert_encoding_closed(w)
    }
  }
}
