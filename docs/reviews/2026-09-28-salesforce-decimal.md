# Salesforce Number as decimal

This records how a Salesforce Number field (describe type `double`) is
declared, read and written as an ActQL `decimal(P,S)`, and why the precision
limit is 15. It follows `2026-09-28-salesforce-date-datetime.md`, which set
out the types and the held items. `percent`, `currency` and `time` stay held
as described there. The common Host, Checkpoint, SDK connection and the
credential transport are unchanged, and no contract version changes.

## What the connector guarantees

Two properties are kept apart:
- **Exact value:** a binary64 value is not a decimal. `0.1` has no exact
  binary64 value. The connector never forms or reads a binary64 value of a
  Number. Every step works on decimal text.
- **Round trip:** a decimal of at most 15 significant digits is recovered
  unchanged from its nearest binary64 value. No two such decimals share one.

Salesforce documents Number values as `double` and replies with a JSON
number. The connector reads the reply's number text. It assumes that text
denotes the double Salesforce holds, as any correct rendering does. The
field's described precision P and scale S bound every value it holds.

- **P ≤ 15 (declared).** Let the reply text R have every nonzero digit
  within the declared positions. Then R is a decimal of at most 15 digits
  that maps to the same double as the stored decimal D, so R = D by the
  round trip. A reply with a digit outside the positions is refused (below).
  Either way, no wrong value within the declared type is admitted.
- **P 16–18 (not declared).** Two stored decimals can share one double. A
  different decimal within the declared scale could then come back and pass
  every check. Such fields are listed as `unsupported_precision`.

The limit follows from binary64 and the documented `double` transport, not
from "every value is a Java double". ActQL's `decimal` allows P ≤ 38, so the
ActQL side does not limit it further.

**Write.** The approved decimal's text is sent as the JSON number with the
same digits, trailing zeros included. Nothing is rounded. The guarantee is
that the connector sends the approved value without precision loss; what
Salesforce stores after parsing it, or after a trigger, is outside that
guarantee. For P ≤ 15 the round trip means the approved decimal reads back
unchanged, unless a provider automation changes it.

## Rules

| Step | Rule |
|---|---|
| Declaration | `double` with described `precision` 1–15 and `scale` 0–P → `{type: decimal, precision: P, scale: S}`, for reads and writes. Missing, invalid or larger precision → excluded as `{kind: unsupported_precision, native_type: double, precision, scale}`. |
| Describe metadata | `precision` and `scale` are projected for `double` fields only, and compared when a field's meaning is rechecked (read projection, write projection, declared use). |
| Read (query page, peek) | The cell's exact JSON number text is taken from the reply bytes. It is converted from its digits alone, exponent form included, to fixed-scale text, then admitted by the common decimal admission. Trailing zeros beyond S are exact and dropped. |
| Observed target (Preview before value) | The same conversion; a value outside the decimal makes the observation invalid. |
| Write body | The approved value must be the canonical ActQL text of `decimal(P,S)` (a JSON string). It is sent as the JSON number with the same digits (`decimal_number_value`, which writes text and never parses it into a number). The body keeps the row twice: the provider body, and the row as ActQL values. |
| Preview | States the row as ActQL values (decimal text), from `salesforceSingleWriteRequestValue`. The Preview identity footprint compares that value. |
| Recovery | Rebuilds the request from the approved ActQL row. The rebuilt provider body is the same text. |
| Collections | Each row is rebuilt from its ActQL values and sends the same number text. |

## Where a number passed through binary64, and what changed

| Place | Before | Now |
|---|---|---|
| `emit_write_cell` `double` | `@decode.finite_number`, then `number_value` (binary64) | The approved decimal text, checked against `decimal(P,S)`, written by `@encode.decimal_number_value` |
| `read_field_contract` (peek and query) | `double` as binary64 `number` | `decimal(P,S)` from the reply's number text |
| Observed target value | binary64 | The same text conversion |
| `installed-salesforce-effect.mjs` `JSON.parse(proposal.changesWire)` | Would parse a number | The approved row carries a decimal as a JSON string, so no number is parsed |
| `salesforce-effect-preview.mjs` `parseExactJson` | Parsed the provider body | Parses the ActQL row, where a decimal is a string. A number there still fails as lossy, as before |
| Collections row rebuild | Re-read the provider body | Rebuilt from the ActQL row |

## Typed failures

- **Acquisition:** `SalesforceValueViolation` with
  `{resource, field, expected_type: "decimal", kind}`. `kind` is one of:
  - `scale`: a nonzero digit beyond S;
  - `range`: more integer digits than P−S;
  - `type`: a string, boolean or other non-number;
  - `null` or `missing` on a required field.

  The whole acquisition fails, and no Named Result is published. The value
  is never included, and nothing is rounded.
- **Write:** `SalesforceWriteValueRefused` with `kind` one of `scale`,
  `range`, `format` (not the canonical text, e.g. `"12.5"` for scale 2, an
  exponent, or a JSON number) or `null`. It is refused before any row is
  sent.

## Compatibility

Not a compatibility commitment (pre-v0.1). A Resource with Number fields now
declares them, so its Catalog CID changes, and an earlier publication must
be published again. A Number field no longer reads or writes as binary64
`number`. A Program or Mapping that used it that way must use its decimal
type.

## Tests

| What | Where |
|---|---|
| Number text → decimal, exponent form and trailing zeros; scale, range and format refusals; bounded exponents | `decimal_wbtest.mbt` |
| Canonical approved text; the provider body's number text; the ActQL row; binary64 input refused | `decimal_wbtest.mbt`, `write_body_wbtest.mbt` |
| Query page admission and typed violations without the value; P 16 refused for read and write | `decimal_wbtest.mbt` |
| Observed target value, Preview row values, recovery rebuilding the same body, Collections row bodies | `decimal_wbtest.mbt` |
| Declaration: decimal contract for P 15, `unsupported_precision` for P 16 | `declaration_wbtest.mbt` |
| `decimal_number_value` accepts only exponent-free decimal text | `encode_core/writer_wbtest.mbt` |
| Standard Host: replies `1.2345678E7`, null and `-9999999999999.9` reach the Named Result as `12345678.00`, null and `-9999999999999.90`; a P 16 field fails Check with no I/O | `standard-host.integration.test.mjs` |
| Standard Host: `12.345` at scale 2 fails the acquisition with `kind: scale` | `standard-host.integration.test.mjs` |
| Installed Effect: approved `9999999999999.99` and `-0.10` are sent as exactly that number text; the Preview states the decimal text and the observed before value | `installed-salesforce-effect.test.mjs` |

Mutation check: truncating digits beyond the scale instead of refusing them
fails the e2e violation test and 4 wbtests.

## Remaining

- Number fields above precision 15 stay undeclared. Declaring them needs a
  documented guarantee that the reply text is the stored decimal.
- `percent` and `currency`, as held in the date and datetime review.
