// Limited public-wire numeric admission from docs/design/json-encoding.md.
// Schema constraints and contract-specific length units remain with their
// existing generators; this projection does not normalize received values.
export function finiteWireNumberSource(target) {
  switch (target) {
    case 'js': return `function finiteWireNumber(value) {\n  return Number.isFinite(value) && !Object.is(value, -0);\n}\n\n`;
    case 'python': return `def _finite_number(value):
    try:
        return math.isfinite(value) and not (value == 0 and math.copysign(1, value) < 0)
    except OverflowError:
        return False


`;
    case 'native': return `///|
fn wire_finite_number(number : Double) -> Bool {
  !number.is_nan() && !number.is_inf() &&
  number.reinterpret_as_uint64() != 0x8000000000000000UL
}

`;
    default: throw Error('UnsupportedWireNumericTarget:'+target);
  }
}

// ECMAScript RegExp \s (the registered canonical-value field-name grammar).
// U+0085, U+180E and U+200B are intentionally not whitespace in this grammar.
export const wireWhitespaceCodePoints = Object.freeze([
  9,10,11,12,13,32,160,5760,8192,8193,8194,8195,8196,8197,8198,8199,
  8200,8201,8202,8232,8233,8239,8287,12288,65279,
]);
export const wireFieldNamePattern = '^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$';
export function pythonWirePatternSource() {
  return `def _pattern_matches(pattern, value):
    if pattern == ${JSON.stringify(wireFieldNamePattern)}:
        return (value != '' and value != '__cid' and not value.startswith('__actql_') and '.' not in value
                and any(ord(character) not in (${wireWhitespaceCodePoints.join(',')},) for character in value))
    return re.search(pattern, value, re.ASCII) is not None


`;
}
