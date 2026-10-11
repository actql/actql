import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const stringSignature = 'Exactly two string operands; the result is boolean and is nullable exactly when either operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.';
const stringEvaluation = 'Evaluate the value and then the prefix or suffix once each when demanded, including both children when the first produces NULL. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Exact matching does not skip logical operand charges.';
export const googleScalarLaws = {
  pow: {
    "signature": "Exactly two finite binary64 Number operands; the result is Number and is nullable exactly when either operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC or non-finite overload is admitted.",
    "value": "Return the first operand raised to the second. With non-null operands, a negative base requires an integral exponent, tested in binary64 without narrowing to a bounded integer. Either sign of zero with a negative exponent fails with the existing arithmetic failure. Zero to zero is one. A non-finite result from finite inputs fails with the existing arithmetic failure. Preserve representable subnormal results and return canonical positive zero for unrepresentable underflow or either zero sign. Either NULL operand produces NULL after both child evaluations succeed, before validating these value-domain rules.",
    "algorithm": "Use the selected target's pinned MoonBit core math pow primitive with the explicit finite-input domain checks. GoogleSQL finite-FLOAT64 domain, underflow and overflow behavior is the compatibility target. General last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Evaluate the base then exponent exactly once when demanded, including the second child after a NULL result. Apply strict NULL only after both child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical work, frame, workspace and live-value budgets. Reuse the canonical binary scalar evaluator; do not reevaluate children or add a frontend evaluator.",
    "identity": "The closed source form is {pow: [base, exponent]}; the machine node is {op: pow, body: [base_node, exponent_node]}. SQL POW and POWER and expression-text pow and power lower to the same pow operation. Retain the operation and both ordered children, including constant or mathematically redundant arguments. Earlier contract CIDs retain their earlier meanings. GoogleSQL MOD has no FLOAT64 signature and is not an alias for the existing internal modulo operation."
  },
  exp: {
    "signature": "Exactly one finite binary64 Number operand; the result is Number and is nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC or non-finite overload is admitted.",
    "value": "Return e raised to the operand. Zero produces one. A non-finite result from a finite input fails with the existing arithmetic failure. Preserve representable subnormal results and return canonical positive zero for unrepresentable underflow. NULL produces NULL.",
    "algorithm": "Use the selected target's pinned MoonBit core math exp primitive and canonical finite-result validation. General last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Evaluate the demanded child exactly once. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical work, frame, workspace and live-value budgets. Reuse the canonical unary scalar evaluator.",
    "identity": "The closed source form is {exp: expression}; the machine node is {op: exp, body: expression_node}. Retain the operation and child in canonical lowering, including constants. Earlier contract CIDs retain their earlier meanings."
  },
  ln: {
    "signature": "Exactly one finite binary64 Number operand; the result is Number and is nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC or non-finite overload is admitted.",
    "value": "Return the natural logarithm of a positive operand. A non-null operand less than or equal to zero fails with the existing arithmetic failure, including either zero sign. One produces canonical positive zero. NULL produces NULL.",
    "algorithm": "Use the selected target's pinned MoonBit core math ln primitive and canonical finite-result validation. General last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Evaluate the demanded child exactly once. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical work, frame, workspace and live-value budgets. Reuse the canonical unary scalar evaluator.",
    "identity": "The closed source form is {ln: expression}; the machine node is {op: ln, body: expression_node}. SQL LN(x) and LOG(x), and expression-text ln(x) and log(x), normalize to this same unary operation. Retain the operation and child, including constants. Earlier contract CIDs retain their earlier meanings."
  },
  log: {
    "signature": "Exactly two finite binary64 Number operands, value then base; the result is Number and is nullable exactly when either operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC or non-finite overload is admitted.",
    "value": "Return the logarithm of the first operand to the second operand's base. With non-null operands, require the value and base to be positive and the base to differ from one; otherwise fail with the existing arithmetic failure. A base strictly between zero and one is valid. Normalize either result zero sign to canonical positive zero. Either NULL operand produces NULL after both child evaluations succeed, before validating these value-domain rules.",
    "algorithm": "Compute the selected target's pinned MoonBit core math ln(value) divided by ln(base), matching the published GoogleSQL finite-FLOAT64 operation structure, then apply canonical finite-result validation. General last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Evaluate value then base exactly once when demanded, including the second child after a NULL result. Apply strict NULL only after both child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical work, frame, workspace and live-value budgets. Reuse the canonical binary scalar evaluator.",
    "identity": "The closed source form is {log: [value, base]}; the machine node is {op: log, body: [value_node, base_node]}. Canonical JSON log is binary only. The one-argument SQL and expression-text LOG form normalizes to ln; the two-argument form retains log. Preserve both ordered children, including constants. Earlier contract CIDs retain their earlier meanings."
  },
  log10: {
    "signature": "Exactly one finite binary64 Number operand; the result is Number and is nullable exactly when the operand is nullable. Untyped NULL takes the unique Number signature. No implicit conversion, distinct INT64, NUMERIC, BIGNUMERIC or non-finite overload is admitted.",
    "value": "Return the base-ten logarithm of a positive operand. A non-null operand less than or equal to zero fails with the existing arithmetic failure, including either zero sign. One produces canonical positive zero. NULL produces NULL.",
    "algorithm": "Use the selected target's pinned MoonBit core math log10 primitive and canonical finite-result validation. General last-bit equality across native, WebAssembly, JavaScript, platform math libraries or live BigQuery is not asserted.",
    "evaluation": "Evaluate the demanded child exactly once. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical work, frame, workspace and live-value budgets. Reuse the canonical unary scalar evaluator.",
    "identity": "The closed source form is {log10: expression}; the machine node is {op: log10, body: expression_node}. Retain the operation and child, including constants. Earlier contract CIDs retain their earlier meanings."
  },
  starts_with: {
    signature: stringSignature,
    value: 'Return whether the second string is an exact prefix of the first, using their retained Unicode scalar sequences with default binary comparison. The empty prefix matches every non-null string, including the empty string. A longer prefix does not match. No normalization, case folding, trimming or locale rule is applied. Either NULL operand produces NULL.',
    evaluation: stringEvaluation,
    identity: 'The closed source form is {starts_with: [value, prefix]}; the machine node is {op: starts_with, body: [value_node, prefix_node]}. Retain the node and both ordered children in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
  ends_with: {
    signature: stringSignature,
    value: 'Return whether the second string is an exact suffix of the first, using their retained Unicode scalar sequences with default binary comparison. The empty suffix matches every non-null string, including the empty string. A longer suffix does not match. No normalization, case folding, trimming or locale rule is applied. Either NULL operand produces NULL.',
    evaluation: stringEvaluation,
    identity: 'The closed source form is {ends_with: [value, suffix]}; the machine node is {op: ends_with, body: [value_node, suffix_node]}. Retain the node and both ordered children in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
  strpos: {
    signature: 'Exactly two string operands; the result is a finite number and is nullable exactly when either operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.',
    value: 'Return the 1-based Unicode scalar position of the first exact occurrence of the second string in the first, or canonical positive zero when absent. An empty second string returns 1 for every non-null first string, including the empty string. Count Unicode scalars, not UTF-8 bytes, UTF-16 code units or grapheme clusters. Default binary comparison preserves retained values without normalization, case folding, trimming or locale rules. Either NULL operand produces NULL. Positions are exact integer values in the existing bounded string domain, represented by ActQL finite binary64 number rather than the GoogleSQL INT64 type.',
    evaluation: 'Evaluate the value and then the subvalue once each when demanded, including both children when the first produces NULL. Apply strict NULL only after both evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Matching preserves logical operand charges; physical search work remains bounded and cancellable.',
    identity: 'The closed source form is {strpos: [value, subvalue]}; the machine node is {op: strpos, body: [value_node, subvalue_node]}. Retain the node and both ordered children in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
  round: {
    signature: 'One finite binary64 number value operand, or exactly two finite binary64 number operands consisting of value and decimal position N; the result is number and is nullable exactly when any operand is nullable. Untyped NULL takes the unique number signature. N uses ActQL number, not a distinct GoogleSQL INT64 type. No implicit conversion, decimal overload, non-finite value or rounding-mode argument is admitted.',
    value: 'With one operand, return the nearest integer, rounding exact halfway cases away from zero, preserving already integral numbers including the largest finite magnitudes. With explicit N and non-null operands, require N to be integral; a fractional N fails with the existing arithmetic failure. N > 323 leaves the value unchanged and N < -308 produces canonical positive zero, with both comparisons before any narrowing to a bounded integer. Otherwise use the selected decimal-position algorithm, with negative N selecting positions left of the decimal point and N = 0 retaining the unary value rule. A non-finite ROUND result fails with the existing arithmetic failure. Use the existing ActQL arithmetic canonical positive zero rule. Either NULL operand produces NULL after both child evaluations succeed, before validating the integral N value rule.',
    algorithm: 'For explicit decimal position select google/googlesql commit 81c15b796138185c046aefe852321011fdf96615, googlesql/common/round_decimal.cc DecimalRounding<false>/RoundDecimal and googlesql/common/double_double.h Full<double>, using the portable non-FMA ComputeDekkerProduct/Split path. Preserve the reference range reductions, exact power-of-five high/low pairs high = RN(5^k), low = RN(5^k - high) for -323 <= k <= 323, FromSum/Fast2Sum correction order, 2^-105 relative-error threshold, sticky-bit adjustment, signed halfway-away selection and Full-by-Full multiply order. RN is binary64 nearest ties-to-even at each prescribed operation. Take the final product high component before the separate final binary power scaling, retaining the additional subnormal rounding. No FMA, reassociation, single binary64 x*10^N calculation or ideal exact-rational decimal rounding may replace this sequence. This pins the selected finite-FLOAT64 algorithm, not live BigQuery behavior or the full INT64/NUMERIC/BIGNUMERIC overload family.',
    evaluation: 'Evaluate each demanded operand exactly once in authored order, value before explicit N, including the second child after a NULL value. Apply strict NULL only after all demanded child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing work, frame, workspace and live-value budgets. Decimal-position work remains bounded and cancellable; mathematical no-op cases retain logical operand charges. Unary ROUND introduces no secondary evaluation or value-domain failure for an admitted finite number.',
    identity: 'The closed source forms are {round: expression} and {round: [value, N]}; the machine node is {op: round, body: expression_node} or {op: round, body: [value_node, N_node]} respectively. Preserve existing unary canonical bytes. Retain the authored ROUND node and every ordered child, including explicit N = 0 and no-op positions; do not fold them into a unary node or constant. Earlier expression contract CIDs retain their earlier meanings and do not acquire the decimal-position overload.',
  },
  trunc: {
    signature: 'One finite binary64 number value operand, or exactly two finite binary64 number operands consisting of value and decimal position N; the result is number and is nullable exactly when any operand is nullable. Untyped NULL takes the unique number signature. N uses ActQL number, not a distinct GoogleSQL INT64 type. No implicit conversion, decimal overload, non-finite value or rounding-mode argument is admitted.',
    value: 'With one operand, return the integer obtained by discarding the fractional part toward zero, preserving already integral numbers including the largest finite magnitudes. With explicit N and non-null operands, require N to be integral; a fractional N fails with the existing arithmetic failure. N > 323 leaves the value unchanged and N < -308 produces canonical positive zero, with both comparisons before any narrowing to a bounded integer. Otherwise use the selected decimal-position algorithm, with negative N selecting positions left of the decimal point and N = 0 retaining the unary value rule. TRUNC cannot overflow for admitted finite inputs and integral N. Use the existing ActQL arithmetic canonical positive zero rule. Either NULL operand produces NULL after both child evaluations succeed, before validating the integral N value rule.',
    algorithm: 'For explicit decimal position select google/googlesql commit 81c15b796138185c046aefe852321011fdf96615, googlesql/common/round_decimal.cc DecimalRounding<true>/TruncDecimal and googlesql/common/double_double.h Full<double>, using the portable non-FMA ComputeDekkerProduct/Split path. Preserve the reference range reductions, exact power-of-five high/low pairs high = RN(5^k), low = RN(5^k - high) for -323 <= k <= 323, FromSum/Fast2Sum correction order, 2^-105 relative-error threshold, sticky-bit adjustment, toward-zero selection with the reference negative-correction floor rule and Full-by-Full multiply order. RN is binary64 nearest ties-to-even at each prescribed operation. Take the final product high component before the separate final binary power scaling, retaining the additional subnormal rounding. No FMA, reassociation, single binary64 x*10^N calculation or ideal exact-rational decimal rounding may replace this sequence. This pins the selected finite-FLOAT64 algorithm, not live BigQuery behavior or the full INT64/NUMERIC/BIGNUMERIC overload family.',
    evaluation: 'Evaluate each demanded operand exactly once in authored order, value before explicit N, including the second child after a NULL value. Apply strict NULL only after all demanded child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing work, frame, workspace and live-value budgets. Decimal-position work remains bounded and cancellable; mathematical no-op cases retain logical operand charges. Unary TRUNC introduces no secondary evaluation or value-domain failure for an admitted finite number.',
    identity: 'The closed source forms are {trunc: expression} and {trunc: [value, N]}; the machine node is {op: trunc, body: expression_node} or {op: trunc, body: [value_node, N_node]} respectively. Preserve existing unary canonical bytes. Retain the authored TRUNC node and every ordered child, including explicit N = 0 and no-op positions; do not fold them into a unary node or constant. Earlier expression contract CIDs retain their earlier meanings and do not acquire the decimal-position overload.',
  },
  trim: {
    signature: "One string value operand, or exactly two string operands consisting of value and explicit character set; the result is string and is nullable exactly when any operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.",
    value: "Remove the longest leading and trailing sequences of Unicode code points belonging to the selected set. When the set is omitted, use the pinned Unicode 16.0 White_Space set: U+0009..U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F and U+3000. An explicit set is the code points of the second string, independently of order and duplicates; an empty set leaves the value unchanged. Membership is not substring, grapheme-cluster or normalized matching. Combining marks are independently removable even when part of a different combining sequence. Preserve the exact remaining Unicode scalar sequence without normalization, case folding or line-break conversion. An empty value remains empty; a value consisting entirely of set members becomes empty. U+FEFF, U+200B and U+180E are excluded from the omitted set but can be explicit members. Either NULL operand produces NULL.",
    evaluation: "Evaluate each demanded operand exactly once in authored order, value before explicit set, including the second child after a NULL value. Apply strict NULL only after all demanded child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Trimming preserves all logical operand charges; physical set membership, scanning, exact output sizing and construction remain bounded and cancellable.",
    identity: "The closed source forms are {trim: expression} and {trim: [value, characters]}; the machine node is {op: trim, body: expression_node} or {op: trim, body: [value_node, characters_node]} respectively. Preserve existing unary canonical bytes. Retain the authored operation and every ordered child, including empty, duplicate or reordered set expressions, even when the value is unchanged. Earlier expression and scalar-law contract CIDs retain their earlier meanings and do not acquire the explicit-set overload.",
  },
  ltrim: {
    signature: "One string value operand, or exactly two string operands consisting of value and explicit character set; the result is string and is nullable exactly when any operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.",
    value: "Remove the longest leading sequence only of Unicode code points belonging to the selected set. When the set is omitted, use the pinned Unicode 16.0 White_Space set: U+0009..U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F and U+3000. An explicit set is the code points of the second string, independently of order and duplicates; an empty set leaves the value unchanged. Membership is not substring, grapheme-cluster or normalized matching. Combining marks are independently removable even when part of a different combining sequence. Preserve the exact remaining Unicode scalar sequence without normalization, case folding or line-break conversion. An empty value remains empty; a value consisting entirely of set members becomes empty. U+FEFF, U+200B and U+180E are excluded from the omitted set but can be explicit members. Either NULL operand produces NULL.",
    evaluation: "Evaluate each demanded operand exactly once in authored order, value before explicit set, including the second child after a NULL value. Apply strict NULL only after all demanded child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Trimming preserves all logical operand charges; physical set membership, scanning, exact output sizing and construction remain bounded and cancellable.",
    identity: "The closed source forms are {ltrim: expression} and {ltrim: [value, characters]}; the machine node is {op: ltrim, body: expression_node} or {op: ltrim, body: [value_node, characters_node]} respectively. Preserve existing unary canonical bytes. Retain the authored operation and every ordered child, including empty, duplicate or reordered set expressions, even when the value is unchanged. Earlier expression and scalar-law contract CIDs retain their earlier meanings and do not acquire the explicit-set overload.",
  },
  rtrim: {
    signature: "One string value operand, or exactly two string operands consisting of value and explicit character set; the result is string and is nullable exactly when any operand is nullable. Untyped NULL takes the unique string signature. No implicit conversion, BYTES overload or explicit collation is admitted.",
    value: "Remove the longest trailing sequence only of Unicode code points belonging to the selected set. When the set is omitted, use the pinned Unicode 16.0 White_Space set: U+0009..U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F and U+3000. An explicit set is the code points of the second string, independently of order and duplicates; an empty set leaves the value unchanged. Membership is not substring, grapheme-cluster or normalized matching. Combining marks are independently removable even when part of a different combining sequence. Preserve the exact remaining Unicode scalar sequence without normalization, case folding or line-break conversion. An empty value remains empty; a value consisting entirely of set members becomes empty. U+FEFF, U+200B and U+180E are excluded from the omitted set but can be explicit members. Either NULL operand produces NULL.",
    evaluation: "Evaluate each demanded operand exactly once in authored order, value before explicit set, including the second child after a NULL value. Apply strict NULL only after all demanded child evaluations succeed. Preserve child failures, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. Trimming preserves all logical operand charges; physical set membership, scanning, exact output sizing and construction remain bounded and cancellable.",
    identity: "The closed source forms are {rtrim: expression} and {rtrim: [value, characters]}; the machine node is {op: rtrim, body: expression_node} or {op: rtrim, body: [value_node, characters_node]} respectively. Preserve existing unary canonical bytes. Retain the authored operation and every ordered child, including empty, duplicate or reordered set expressions, even when the value is unchanged. Earlier expression and scalar-law contract CIDs retain their earlier meanings and do not acquire the explicit-set overload.",
  },
  safe_add: {
    signature: 'Exactly two finite binary64 number operands; the result is nullable number even when both operands are non-nullable. Untyped NULL takes the unique number signature. No implicit conversion, decimal, INT64, NUMERIC or BIGNUMERIC overload, or non-finite value is admitted.',
    value: 'Apply addition with ordinary binary64 rounding. Return NULL for finite-input overflow. Preserve finite results, including subnormals and underflow to zero, and normalize either zero sign to canonical positive zero. Either NULL operand produces NULL.',
    evaluation: 'Evaluate the left and then right child exactly once when demanded, including the right child after a NULL left result. Only an arithmetic error from this operation becomes NULL. Preserve child failures, invalid operand domains, enclosing lazy demand, first-failure order, cancellation and existing control, logical-work, live-byte and workspace budgets. Do not reevaluate children or catch surrounding failures.',
    identity: 'The closed source form is {safe_add: [left, right]}; the closed machine node is {op: safe_add, body: [left_node, right_node]}. Retain the operation and both ordered children in canonical lowering, including constant arguments. Earlier contract CIDs retain their earlier meanings.',
  },
  safe_subtract: {
    signature: 'Exactly two finite binary64 number operands; the result is nullable number even when both operands are non-nullable. Untyped NULL takes the unique number signature. No implicit conversion, decimal, INT64, NUMERIC or BIGNUMERIC overload, or non-finite value is admitted.',
    value: 'Apply subtraction of the second operand from the first with ordinary binary64 rounding. Return NULL for finite-input overflow. Preserve finite results, including subnormals and underflow to zero, and normalize either zero sign to canonical positive zero. Either NULL operand produces NULL.',
    evaluation: 'Evaluate the left and then right child exactly once when demanded, including the right child after a NULL left result. Only an arithmetic error from this operation becomes NULL. Preserve child failures, invalid operand domains, enclosing lazy demand, first-failure order, cancellation and existing control, logical-work, live-byte and workspace budgets. Do not reevaluate children or catch surrounding failures.',
    identity: 'The closed source form is {safe_subtract: [left, right]}; the closed machine node is {op: safe_subtract, body: [left_node, right_node]}. Retain the operation and both ordered children in canonical lowering, including constant arguments. Earlier contract CIDs retain their earlier meanings.',
  },
  safe_multiply: {
    signature: 'Exactly two finite binary64 number operands; the result is nullable number even when both operands are non-nullable. Untyped NULL takes the unique number signature. No implicit conversion, decimal, INT64, NUMERIC or BIGNUMERIC overload, or non-finite value is admitted.',
    value: 'Apply multiplication with ordinary binary64 rounding. Return NULL for finite-input overflow. Preserve finite results, including subnormals and underflow to zero, and normalize either zero sign to canonical positive zero. Either NULL operand produces NULL.',
    evaluation: 'Evaluate the left and then right child exactly once when demanded, including the right child after a NULL left result. Only an arithmetic error from this operation becomes NULL. Preserve child failures, invalid operand domains, enclosing lazy demand, first-failure order, cancellation and existing control, logical-work, live-byte and workspace budgets. Do not reevaluate children or catch surrounding failures.',
    identity: 'The closed source form is {safe_multiply: [left, right]}; the closed machine node is {op: safe_multiply, body: [left_node, right_node]}. Retain the operation and both ordered children in canonical lowering, including constant arguments. Earlier contract CIDs retain their earlier meanings.',
  },
  safe_divide: {
    signature: 'Exactly two finite binary64 number operands; the result is nullable number even when both operands are non-nullable. Untyped NULL takes the unique number signature. No implicit conversion, decimal, INT64, NUMERIC or BIGNUMERIC overload, or non-finite value is admitted.',
    value: 'Apply division of the first operand by the second with ordinary binary64 rounding. Return NULL for finite-input overflow or a zero divisor. Preserve finite results, including subnormals and underflow to zero, and normalize either zero sign to canonical positive zero. Either NULL operand produces NULL. The distinct legacy safe_div keeps its zero-divisor-only rule; it is not an alias of safe_divide.',
    evaluation: 'Evaluate the left and then right child exactly once when demanded, including the right child after a NULL left result. Only an arithmetic error from this operation becomes NULL. Preserve child failures, invalid operand domains, enclosing lazy demand, first-failure order, cancellation and existing control, logical-work, live-byte and workspace budgets. Do not reevaluate children or catch surrounding failures.',
    identity: 'The closed source form is {safe_divide: [left, right]}; the closed machine node is {op: safe_divide, body: [left_node, right_node]}. Retain the operation and both ordered children in canonical lowering, including constant arguments. Earlier contract CIDs retain their earlier meanings.',
  },
  safe_negate: {
    signature: 'Exactly one finite binary64 number operand; the result is number with the operand nullability. Untyped NULL takes the unique number signature. No implicit conversion, decimal, INT64, NUMERIC or BIGNUMERIC overload, or non-finite value is admitted.',
    value: 'Return the arithmetic negation with canonical positive zero. Every admitted finite binary64 value, including both largest magnitudes and subnormals, has a finite negation, so this supported domain introduces no overflow NULL. A NULL operand produces NULL.',
    evaluation: 'Evaluate the sole child exactly once when demanded. Preserve its failure, invalid operand domains, enclosing lazy demand, first-failure order, cancellation and existing control, logical-work, live-byte and workspace budgets. Do not reevaluate the child or catch surrounding failures.',
    identity: 'The closed source form is {safe_negate: expression}; the closed machine node is {op: safe_negate, body: expression_node}. Retain the SAFE_NEGATE node and child in canonical lowering, including constant arguments. Earlier contract CIDs retain their earlier meanings.',
  },
  sign: {
    signature: 'Exactly one finite binary64 number operand; the result is number with the operand nullability. Untyped NULL takes the unique number signature. No implicit conversion, decimal overload or non-finite value is admitted.',
    value: 'Return exactly -1 for a negative finite number, canonical positive zero for either zero sign, and exactly 1 for a positive finite number. This includes subnormal and largest finite magnitudes. NULL produces NULL.',
    evaluation: 'Evaluate the sole child exactly once when demanded, then apply the value rule. Preserve the child failure, enclosing lazy demand, first-failure order, cancellation and existing logical budgets. SIGN introduces no secondary evaluation or value-domain failure for an admitted finite number.',
    identity: 'The closed source form is {sign: expression}; the closed machine node is {op: sign, body: expression_node}. Retain the SIGN node and its child in canonical lowering. Earlier expression contract CIDs retain their earlier meaning.',
  },
};
const templates = {pow: 'contains', exp: 'abs', ln: 'abs', log: 'contains', log10: 'abs', starts_with: 'contains', ends_with: 'contains', strpos: 'contains', sign: 'abs', trim: 'abs', ltrim: 'abs', rtrim: 'abs', round: 'abs', trunc: 'abs', safe_add: 'contains', safe_subtract: 'contains', safe_multiply: 'contains', safe_divide: 'contains', safe_negate: 'abs'};

// Unicode 16.0 PropList.txt White_Space, not host-language trim or regex \s.
export const trimWhiteSpaceCodePoints = [
  '0009..000D', '0020', '0085', '00A0', '1680', '2000..200A',
  '2028', '2029', '202F', '205F', '3000',
];
export function updateTrimScalarLaw(scalar, write = false) {
  assert.equal(scalar.unicode.data_version, '16.0', 'TRIM Unicode data version');
  const expected = {trim: 'unicode-white-space',
    ltrim: 'unicode-white-space-leading', rtrim: 'unicode-white-space-trailing',
    trim_white_space_code_points: trimWhiteSpaceCodePoints,
    trim_character_set: 'unicode-code-point-membership',
    trim_empty_character_set: 'preserve-value'};
  if (write) Object.assign(scalar.unicode, structuredClone(expected));
  else for (const [key, value] of Object.entries(expected)) {
    assert.deepEqual(scalar.unicode[key], value, `stale TRIM scalar law ${key}`);
  }
}

// Copy shapes, not semantics, and keep each embedding's local expression refs.
function visit(value, write, counts) {
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value.oneOf)) {
    for (const kind of ['source', 'node']) {
      const named = (candidate, name) => kind === 'source'
        ? candidate.additionalProperties === false &&
          candidate.required?.length === 1 && candidate.required[0] === name
        : candidate.properties?.op?.const === name;
      for (const [name, template] of Object.entries(templates)) {
        const shapes = value.oneOf.filter(candidate => named(candidate, template));
        if (!shapes.length) continue;
        assert.equal(shapes.length, 1, `ambiguous ${template} expression schema`);
        const expected = structuredClone(shapes[0]);
        if (kind === 'source') {
          expected.required = [name];
          expected.properties = {[name]: expected.properties[template]};
        } else expected.properties.op.const = name;
        if (['trim', 'ltrim', 'rtrim', 'round', 'trunc'].includes(name)) {
          const key = kind === 'source' ? name : 'body';
          const unary = expected.properties[key];
          expected.properties[key] = {oneOf: [unary, {type: 'array',
            minItems: 2, maxItems: 2, items: structuredClone(unary)}]};
        }
        const matches = value.oneOf.filter(candidate => named(candidate, name));
        assert.ok(matches.length <= 1, `duplicate ${name} schema`);
        if (write) {
          if (matches.length) value.oneOf[value.oneOf.indexOf(matches[0])] = expected;
          else value.oneOf.splice(value.oneOf.indexOf(shapes[0]) + 1, 0, expected);
        } else assert.deepEqual(matches[0], expected, `stale ${kind} ${name} schema`);
        counts[name][kind]++;
      }
    }
  }
  for (const child of Object.values(value)) visit(child, write, counts);
}

export function updateSafeArithmeticScalarLaw(scalar, write = false) {
  const expected = {
    domain: 'finite-ieee754-binary64-only',
    safe_add: 'overflow-null',
    safe_subtract: 'overflow-null',
    safe_multiply: 'overflow-null',
    safe_divide: 'zero-divisor-or-overflow-null',
    safe_negate: 'finite-negation-cannot-overflow',
    legacy_safe_div: 'zero-divisor-null-overflow-failure',
    underflow: 'finite-rounded-result-including-canonical-positive-zero',
    boundary: 'only-own-arithmetic-errors-after-once-only-eager-children',
  };
  if (write) scalar.number.safe_arithmetic = structuredClone(expected);
  else assert.deepEqual(scalar.number.safe_arithmetic, expected, 'SAFE arithmetic scalar law');
}

export function updateGoogleScalarContracts(expressions, protocol, grammar, write = false) {
  const counts = Object.fromEntries(Object.keys(templates).map(name =>
    [name, {source: 0, node: 0}]));
  for (const name of Object.keys(templates)) {
    assert.match(grammar, new RegExp(`\\| "${name}"(?:\\s|\\|)`, 'u'),
      `${name} missing from expression grammar`);
  }
  visit(expressions.schemas, write, counts);
  visit(protocol.artifact_schemas, write, counts);
  for (const [name, count] of Object.entries(counts)) {
    assert.ok(count.source > 0 && count.node > 0, `missing ${name} expression schemas`);
    if (write) expressions.laws[name] = structuredClone(googleScalarLaws[name]);
    else assert.deepEqual(expressions.laws[name], googleScalarLaws[name], `stale ${name} law`);
  }
  const grammarSha256 = createHash('sha256').update(grammar).digest('hex');
  if (write) expressions.grammar_sha256 = grammarSha256;
  else assert.equal(expressions.grammar_sha256, grammarSha256, 'stale expression grammar pin');
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) {
    if (write) protocol.artifact_schema_cids[name] = machineCid(schema);
    else assert.equal(protocol.artifact_schema_cids[name], machineCid(schema));
  }
  if (write) protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
  else assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
  return counts;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const paths = ['spec/contracts/actql-expressions.json', 'spec/contracts/actql-protocol-schemas.json'];
  const bodies = paths.map(path => JSON.parse(readFileSync(path, 'utf8')));
  const grammar = readFileSync(bodies[0].grammar, 'utf8');
  const scalarPath = 'spec/dependencies/aoa-rela-scalar-laws.json';
  const aoaPath = 'spec/contracts/actql-aoa.json';
  const scalar = JSON.parse(readFileSync(scalarPath, 'utf8'));
  const aoa = JSON.parse(readFileSync(aoaPath, 'utf8'));
  if (process.argv.includes('--write')) {
    updateTrimScalarLaw(scalar, true);
    updateSafeArithmeticScalarLaw(scalar, true);
    aoa.rela_scalar_law_manifest_cid = machineCid(scalar);
    writeFileSync(scalarPath, JSON.stringify(scalar, null, 2) + '\n');
    writeFileSync(aoaPath, JSON.stringify(aoa, null, 2) + '\n');
    updateGoogleScalarContracts(...bodies, grammar, true);
    bodies.forEach((body, index) => writeFileSync(paths[index], JSON.stringify(body, null, 2) + '\n'));
  }
  updateTrimScalarLaw(scalar);
  updateSafeArithmeticScalarLaw(scalar);
  assert.equal(aoa.rela_scalar_law_manifest_cid, machineCid(scalar), 'TRIM scalar manifest pin');
  console.log('GoogleSQL STRING boundary/search/TRIM/LTRIM/RTRIM and finite-number SIGN/ROUND/TRUNC/SAFE arithmetic contracts verified:',
    updateGoogleScalarContracts(...bodies, grammar));
}
