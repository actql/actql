# Salesforce date and datetime support

This records which Salesforce value types the connector declares, reads and
writes, and on what basis. It also lists which types are held and why. This
change covers `date` (read and write) and `datetime` (read, and whole-second
write). The common Host, Checkpoint, SDK connection and the credential
transport are unchanged, and no contract version changes.

## Type table

"Closed" means the existing ActQL types and value rules fix the meaning with
no new contract. Support is decided per direction: a type is writable only
when its written value means what was approved.

| Salesforce type | Official JSON form | ActQL type | Read | Write | Basis and conditions |
|---|---|---|---|---|---|
| `date` | `"2024-05-22"` (`yyyy-MM-dd`, no offset). Range 1700-01-01 to 4000-12-31 | `date` | Closed | Closed | Same spelling. A written value outside the range is refused before sending. |
| `datetime` | Read in UTC as `"2012-07-12T17:49:01.000+0000"`. Write accepts `...SSSZ` | `timestamp` | Closed | Whole seconds only | Read: only the `+0000` spelling is admitted, as the same instant ending in `Z`. Write: `.000` only, within 1700-01-01T00:00:00Z to 4000-12-31T00:00:00Z. |
| `double` (Number) | JSON number, possibly in exponent form. `precision` and `scale` in the describe | `decimal(P,S)` | P ≤ 15 | P ≤ 15 | See `2026-09-28-salesforce-decimal.md`: read from the reply's number text, written as the same number text; P 16–18 not declared. |
| `percent` | Same JSON number form. Whether 12.5% reads as `12.5` or `0.125` is not documented in the pages checked | — | Held | Held | The scale must come from the API's official contract first. |
| `currency` | Same JSON number form. The amount is in the record's `CurrencyIsoCode` | — | Held | Held | The amount and its currency code must stay together (proposal below). |
| `time` | `"07:00:00.000Z"`, but the `Z` is not UTC: it is the saving user's time zone | None | Held | Held | Needs a common zone-less time-of-day type (proposal below). |
| `long` | Not in the field type table read | — | Not declared | Not declared | Out of this change. |

Declared types are listed in the static declaration. Every excluded field is
listed with `unsupported_type` and its native type.

## Rules

**Read.**
- `date`: the common admission applies the ActQL date rule, a valid
  `YYYY-MM-DD`.
- `datetime`: exactly `yyyy-MM-ddTHH:mm:ss.SSS+0000` becomes the same text
  ending in `Z`, and the common admission then applies the timestamp rule.
  Nothing else is converted:
  - another offset (`+0900`, `-0000`, `+00:00`);
  - the `Z` spelling;
  - a missing or extra fractional digit;
  - a local time or a space separator;
  - an invalid calendar date.
- No local time zone is ever applied.

**Write.**
- The approved ActQL value is sent as it is. Nothing is rounded,
  truncated or converted.
- `date`: a valid `YYYY-MM-DD` within the documented range.
- `datetime`: a canonical ActQL timestamp. Its millisecond part must be
  `.000`, and it must be within the documented range.
- A nonzero millisecond part is refused before sending, never rounded.
- The guarantee is only that the connector sends the approved value without
  loss of precision. The stored value can still differ: a provider trigger,
  workflow or validation can change it after it is received.

**Observed target values.** A target read for the Preview's before value is
an observation, not a write:
- a `datetime` in the `+0000` spelling is read as the same UTC instant, with
  any millisecond part;
- another offset makes the observation invalid.

**Where the whole-second limit is stated.**
- The static declaration lists each writable `datetime` field under the
  writable's `timestamp_whole_seconds`.
- The write capability evidence gives a `datetime` field
  `write_timestamp_precision: "second"`.
- The Mapping's `target_schema` stays `timestamp`: the common Mapping
  contract has no member for this limit.

## Typed failures

**Acquisition.** A provider value that is not a value of its declared type
fails the whole acquisition:
- no null substitution, no row dropped, no rounding;
- the read stops, the attempt is closed, and no Named Result is published;
- the adapter's failure is `SalesforceValueViolation`, with outcome `stopped`;
- its cause carries `violation: {resource, field, expected_type, kind}`;
- `kind` is one of:
  - `format`: not a valid spelling of the type;
  - `type`: the wrong JSON type;
  - `null`: null in a required field;
  - `missing`: a required field is missing.

The value itself is never included. A budget or capture overrun is not a
value violation and keeps its own failure.

**Write.** A row value that is not a value of its declared write type is
refused while the Preview is authored, before any row is sent:
- the failure is `SalesforceWriteValueRefused`;
- it carries `refusal: {resource, field, expected_type, kind}`;
- `kind` is one of `precision`, `range`, `format` or `null`.

**Required runtime entries.** Both entries that report these failures are
required, with no fallback when one is missing:
- The source load refuses a standard runtime without
  `clientProgramSalesforceBroadValueViolation`, or any other issued broad
  read entry, as `InvalidSalesforceSourceRuntime`, before any provider I/O.
- The Site driver refuses a caller without
  `salesforceIssuedBroadValueViolation` as `InvalidSalesforceIssuedBroadRead`.
- The Effect load refuses a Salesforce runtime without
  `salesforceWriteValueRefusal` as `InvalidSalesforceEffectRuntime`.

## Compatibility

For a Resource with `date` or `datetime` fields, the generated Catalog now
declares them, so its CID changes. A Host start restores a publication by
regenerating the declaration and comparing that CID. An earlier publication
of such a Resource is therefore refused (`ForeignSalesforceDeclaration`) and
must be published again. Resources without these fields are unchanged.

## Tests

| What | Where |
|---|---|
| Declaration per direction; `time`, `double`, `percent`, `currency` excluded with reasons; `timestamp_whole_seconds` | `declaration_wbtest.mbt` |
| Read: the `+0000` spelling becomes `Z`; the date as it is; nulls kept; every other spelling a typed `format` violation without the value; `type` and `null` violations; a budget overrun is not a violation | `temporal_wbtest.mbt` |
| Write: sent as approved, range bounds included; milliseconds refused as `precision`; range and format refusals; typed refusal JSON | `temporal_wbtest.mbt` |
| Observed target `+0000` value as the Preview's before value; capability evidence states whole seconds | `temporal_wbtest.mbt` |
| Standard Host: declaration → acquisition → Named Result equals values fixed independently from the org's stored replies | `standard-host.integration.test.mjs` "Salesforce dates and UTC datetimes reach the Named Result" |
| Standard Host: a `+0900` reply fails the Run, publishes nothing, sends one query; the adapter states `SalesforceValueViolation` after `stopped`; a capture overrun is not a violation | `standard-host.integration.test.mjs` |
| Installed Effect: the Preview's after values and the provider PATCH bodies equal the approved values; the observed `+0000` before value is the UTC instant | `installed-salesforce-effect.test.mjs` "an approved date and whole-second timestamp" |
| Installed Effect: milliseconds, and a date or datetime out of range, are refused typed with no write sent | `installed-salesforce-effect.test.mjs` "a written value outside its declared type" |
| A missing violation or refusal entry is refused before provider I/O (source load, Site driver, Effect load) | `standard-host.integration.test.mjs`, `salesforce-catalog-sync.test.mjs`, `installed-salesforce-effect.test.mjs` "without the value … entry" |

Mutation checks:
- Removing the whole-second check fails the write refusal e2e test and the
  write wbtests.
- Accepting any offset fails the violation e2e test and the read wbtests.

## Decimal Number (`double`)

Implemented after this change; see `2026-09-28-salesforce-decimal.md` for
the basis of the precision limit, the rules, and the binary64 path audit.

## Held: `percent`

The numeric form is the same as `double`. The pages checked do not document
the scale: whether 12.5% is `12.5` or `0.125` through the API. The next step
is the API's official contract for the percent type, from the REST and SOAP
field type references and the describe's `precision`/`scale`. A live org is
not assumed to be required.

## Held: `currency` (proposal)

An amount means nothing without its currency. Proposal:
- A currency field is declared only as a pair with the record's
  `CurrencyIsoCode` (`string`, not null) in the same SourceView. A read
  projection that selects the amount without the code is refused at
  preparation.
- In an org without multiple currencies there is no `CurrencyIsoCode`
  field. Such a field is declared only with a Catalog fact naming the org's
  single currency, taken from the connection, not from a row.
- A write of an amount must name the code it assumes. It is refused before
  sending when the target record's observed `CurrencyIsoCode` differs.
- The amount itself uses the decimal rule above. No new currency scalar is
  needed for this proposal; it is a declaration and Mapping rule.

## Held: `time` (contract proposal)

Salesforce's `time` is a time of day in the saving user's time zone,
although it is written with `Z`. The value alone does not reveal that zone.
Proposed common scalar: **`time`**, a time of day with no date and no zone.

| | Proposed rule |
|---|---|
| Canonical JSON | String `HH:mm:ss.sss`: exactly 12 characters, three fractional digits, 00:00:00.000 to 23:59:59.999. No offset and no `Z`. |
| Meaning | A wall-clock time with no zone. It is never converted to or from UTC or any local zone, and never combined implicitly with a date. |
| Order and equality | Chronological, equal to the canonical text order. |
| Casts | `TIME(x)` accepts only the canonical string. No cast from `timestamp`, which would need a zone. |
| Contract diff | `language.md` type list and casts; `value_contract` `Shape::Time`; `value_admission` rule (12 characters, ranges); check-environment schema type `"time"`. |

Salesforce mapping under this proposal:
- **Read** `"07:00:00.000Z"` → `"07:00:00.000"`. The documented literal `Z`
  is dropped as the documented non-UTC marker; no zone is inferred.
- **Write** `"07:00:00.000"` → `"07:00:00.000Z"`, the documented input form.
- `"07:00:00.000+0900"` or `"07:00"` → typed violation.

The connector implements none of this until the common type exists.
