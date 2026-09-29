# Salesforce Number as decimal

This records how a Salesforce Number field (describe type `double`) is
declared, read and written as an ActQL `decimal(P,S)`, what that
guarantees, and the chosen precision range. It follows `2026-09-28-salesforce-date-datetime.md`, which set
out the types and the held items. `percent`, `currency` and `time` stay held
as described there. The common Host, Checkpoint, SDK connection and the
credential transport are unchanged, and no contract version changes.

## What the connector guarantees

The guarantee covers only what the connector does with the text it
receives and sends:
- **Read:** the value that the reply's JSON number text denotes is admitted
  as the ActQL decimal, without rounding. A value that does not fit the
  declared `decimal(P,S)` is refused.
- **Write:** the connector sends JSON whose number denotes the approved
  decimal, with the same digits.
- **Not guaranteed:**
  - Salesforce's internal value.
  - The value stored after a write, including rounding and automation.
  - Precision lost before the reply.

  Salesforce documents that a value written through the API or Apex can
  carry more fractional digits than the field defines. So a field's
  described precision and scale do not bound every value it holds, and a
  read cannot prove that the reply equals the value held.

**The support range P ≤ 15 is a choice, not a proof.**
- A Number field is declared only when its described precision is at most
  15.
- Nothing is claimed about recovering the stored value exactly.
- Fields above 15 stay undeclared (`unsupported_precision`) until there is
  a reason to extend the range.

**binary64.** The connector does not compute a decimal's value through
binary64:
- the read converts the number text's digits;
- the write copies the approved decimal text as the number.

It does call `finite_number()` on a reply cell (`query_page.mbt`, and the
observed target value in `write_body.mbt`). That call only checks that the
cell is a JSON number. Its binary64 result is not used.

## Rules

| Step | Rule |
|---|---|
| Declaration | `double` with described `precision` 1–15 and `scale` 0–P → `{type: decimal, precision: P, scale: S}`, for reads and writes. Missing, invalid or larger precision → excluded as `{kind: unsupported_precision, native_type: double, precision, scale}`. |
| Describe metadata | `precision` and `scale` are projected for `double` fields only, and compared when a field's meaning is rechecked (read projection, write projection, declared use). |
| Read (query page, peek) | The cell's exact JSON number text is taken from the reply bytes. Its value is computed from its digits, exponent form included, as fixed-scale text, then admitted by the common decimal admission. Trailing zeros beyond S are exact and dropped. |
| Observed target (Preview before value) | The same conversion; a value outside the decimal makes the observation invalid. |
| Write body | The approved value must be the canonical ActQL text of `decimal(P,S)` (a JSON string). It is sent as the JSON number with the same digits (`decimal_number_value` copies the text). The body keeps the row twice: the provider body, and the row as ActQL values. |
| Preview | States the row as ActQL values (decimal text), from `salesforceSingleWriteRequestValue`. It is a required Effect runtime entry, with no fallback to the provider body. The Preview identity footprint compares that value. |
| Recovery | Rebuilds the request from the approved ActQL row. The rebuilt provider body is the same text. |
| Collections | Each row is rebuilt from its ActQL values and sends the same number text. |

## Where a number passed through binary64, and what changed

| Place | Before | Now |
|---|---|---|
| `emit_write_cell` `double` | `@decode.finite_number`, then `number_value` (binary64) | The approved decimal text, checked against `decimal(P,S)`, copied by `@encode.decimal_number_value` |
| `read_field_contract` (peek and query) | `double` as binary64 `number` | `decimal(P,S)` from the reply's number text |
| Observed target value | binary64 | The same text conversion (`finite_number` only checks that it is a number) |
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
| Installed Effect: a runtime without `salesforceSingleWriteRequestValue` (or `salesforceWriteValueRefusal`) is refused at load with `InvalidSalesforceEffectRuntime`, with no provider I/O | `installed-salesforce-effect.test.mjs` "missing a required entry" |

Mutation checks:
- Truncating digits beyond the scale instead of refusing them fails the e2e
  violation test and 4 wbtests.
- Dropping `salesforceSingleWriteRequestValue` from the Effect runtime's
  required list fails the load test.

## Remaining

- Number fields above precision 15 stay undeclared. The support range is
  a choice; extending it needs its own reason.
- `percent` and `currency`, as held in the date and datetime review.
