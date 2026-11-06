///|
fn sf_initialization_base64_digit(code : Int) -> Int {
  if code >= 65 && code <= 90 {
    code - 65
  } else if code >= 97 && code <= 122 {
    code - 97 + 26
  } else if code >= 48 && code <= 57 {
    code - 48 + 52
  } else if code == 43 {
    62
  } else if code == 47 {
    63
  } else {
    -1
  }
}

///|
fn sf_initialization_wire_node_increment(byte : Int) -> Int64 {
  if byte == 123 || byte == 91 {
    2L
  } else if byte == 58 || byte == 44 || byte == 92 {
    1L
  } else {
    0L
  }
}

///|
// Read the SAME canonical Base64 original without allocating decoded Bytes,
// text, a parser or a tree. Root + two slots per container + one per field,
// separator and escape bounds all parsed/failed prefixes. Count punctuation
// inside strings too; UTF-8 continuation bytes cannot hide ASCII delimiters.
// This is representation demand DATA, never JSON/Describe admission.
fn sf_initialization_original_geometry(
  encoded : String,
  max_bytes : Int,
  max_nodes : Int,
) -> (Int, Int)? {
  let length = encoded.length()
  if max_bytes < 1 || max_nodes < 1 || length % 4 != 0 {
    return None
  }
  let padding = if length > 0 && encoded[length - 2] == '=' {
    2
  } else if length > 0 && encoded[length - 1] == '=' {
    1
  } else {
    0
  }
  let bytes = length / 4 * 3 - padding
  if bytes > max_bytes {
    return None
  }
  let mut nodes = 1L
  for index = 0; index < length; index = index + 4 {
    let a = sf_initialization_base64_digit(encoded[index].to_int())
    let b = sf_initialization_base64_digit(encoded[index + 1].to_int())
    let c = sf_initialization_base64_digit(encoded[index + 2].to_int())
    let d = sf_initialization_base64_digit(encoded[index + 3].to_int())
    if a < 0 || b < 0 {
      return None
    }
    nodes += sf_initialization_wire_node_increment((a << 2) | (b >> 4))
    if encoded[index + 2] == '=' {
      if index + 4 != length || encoded[index + 3] != '=' || (b & 15) != 0 {
        return None
      }
    } else {
      if c < 0 {
        return None
      }
      nodes += sf_initialization_wire_node_increment(((b & 15) << 4) | (c >> 2))
      if encoded[index + 3] == '=' {
        if index + 4 != length || (c & 3) != 0 {
          return None
        }
      } else {
        if d < 0 {
          return None
        }
        nodes += sf_initialization_wire_node_increment(((c & 3) << 6) | d)
      }
    }
  }
  Some((bytes, Int64::min(nodes, max_nodes.to_int64()).to_int()))
}

///|
/// One original recovery pass with the unchanged full wire/text, normalizing
/// parsers, field bound and writer limits. Only its tree-node demand uses
/// measured structural punctuation. The length-only entry keeps its complete
/// conservative fallback; neither entry changes producer or admission rules.
pub fn initialization_original_construction_capacity(
  encoded_bodies : Array[String?],
  observation_units : Int,
  name_lengths : Array[Int],
  binding_units : Int,
  connector_units : Int,
  revision_units : Int,
  describe : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  limits : @catalog.DeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if encoded_bodies.is_empty() || encoded_bodies.length() > 200 {
    return None
  }
  let lengths = []
  let nodes = []
  let mut encoded_units = 0L
  for original in encoded_bodies {
    match original {
      None => {
        lengths.push(0)
        nodes.push(1)
      }
      Some(encoded) => {
        guard sf_initialization_original_geometry(
            encoded,
            describe.max_bytes,
            describe.max_nodes,
          )
          is Some((bytes, bound)) else {
          return None
        }
        encoded_units += encoded.length().to_int64()
        if encoded_units > 2147483647L {
          return None
        }
        lengths.push(bytes)
        nodes.push(bound)
      }
    }
  }
  sf_initialization_construction_capacity(
    lengths,
    nodes,
    encoded_units.to_int(),
    observation_units,
    name_lengths,
    binding_units,
    connector_units,
    revision_units,
    describe,
    max_observation_bytes,
    limits,
  )
}
