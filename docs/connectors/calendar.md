# Google Calendar

The Google Calendar Connector reads calendars, events and free/busy
information, and creates, updates, upserts and deletes events, answers
invitations and moves events between calendars. A Program can look at what is
scheduled, decide with a model what needs a follow-up, and put it on the
calendar.

## Sources

- `calendar.calendars` — the calendars the account can see: `id`, `summary`,
  `time_zone`, `access_role`. Key `id`.
- `calendar.events` — events: `id`, `ical_uid`, `calendar_id`, `summary`,
  `description`, `start`, `end`, `all_day`, `location`, `status`, `organizer`,
  `attendees` (an array of objects with `email`, `response_status`,
  `optional`), `recurring_event_id`, `created`, `updated`, `etag`. Key
  (`calendar_id`, `id`). `ical_uid` identifies the same logical event across
  calendars, but recurring instances can share it; it is not an additional
  row key. Filter by calendar and time range; recurring events are expanded
  into instances.
- `calendar.free_busy` — busy intervals for a calendar in a time range:
  `calendar_id`, `start`, `end`. Filter by calendar and time range; the
  source has no key.

## Types

| Calendar | ActQL | Notes |
| --- | --- | --- |
| `id`, `calendar_id` | `string` | Required original identifiers and the row key. |
| `iCalUID`, `recurringEventId` | `string?` | Original identifiers when available. |
| `start`/`end` `dateTime` | `timestamp?` | Preserve the exact instant; `all_day = false` when start is known. An omitted offset requires that endpoint's explicit `timeZone` in the selected CalendarProfile. |
| `start`/`end` `date` | `timestamp?` | All-day boundaries are independent midnights in the original calendar zone, using the selected CalendarProfile; `all_day = true`. End is exclusive. No process timezone is substituted. |
| `all_day` | `bool?` | NULL when the original start is unavailable. |
| `summary`, `description`, `location` | `string?` | Original text when available, without normalization. |
| `organizer` | `string?` | Original organizer email when available; no ID or display-name fallback. |
| `attendees[]` | `array<struct<email string, response_status string, optional bool>>?` | The complete list, in original order, or NULL when completeness is unavailable. `response_status` is `needsAction`, `declined`, `tentative` or `accepted`; omitted native `optional` means false. |
| `status` | `string?` | Original `confirmed`, `tentative` or `cancelled`; no inferred status. |
| `etag` | `string?` | Original version when available; writes still require their actual version guard. |
| `created`, `updated` | `timestamp?` | Exact original instant normalized to UTC. |

A cancelled or deleted item may contain only its `id`. Its unavailable cells
are NULL, with the actual `calendar_id` and supplied status retained. When
`endTimeUnspecified` is true, `end` is NULL: the API's compatibility end is
validated when present but is not an actual end.

An omitted/null attendee list, `attendeesOmitted`, an attendee whose email or
response status is missing, or a pending attendee operation makes the whole
`attendees` cell NULL; other available columns remain readable. A complete
empty list is `[]`. No email or response status is invented. Present malformed
values still refuse the row, including inside an incomplete list. Native
optional booleans use their documented omitted default only; explicit null is
not that default. See the
[row-contract decision](../design/semantic-decisions.md#calendar-event-unavailable-cells).

Writes convert in the other direction with the same rules; an all-day event
is written by setting `all_day = TRUE` and `date`-typed `start` and `end`.

## Effects and operations

Record Effects write by key:

- **insert** — `EFFECT INSERT calendar.events (calendar_id, summary, start, end, …) VALUES (…)`.
- **update** — `EFFECT UPDATE calendar.events ID id SET (…)`.
- **upsert** — `EFFECT UPSERT calendar.events ID ical_uid SET (calendar_id = …, summary = …, start = …, end = …, …)`
  creates the event or updates the one with that `iCalUID` — the way to keep
  a calendar in step with a source system without duplicating events.
- **delete** — `EFFECT DELETE calendar.events ID id`.

`id` identifies exactly one event within its calendar; `ical_uid` identifies
it across calendars. `ID id` is enough because the row's `calendar_id` column
names the calendar; a row without it is refused at `check`. Setting `send_updates = 'all'` on an insert, update or
delete sends invitations or cancellations to attendees; the default makes
the change silently.

Operations:

- **respond** — `EFFECT COMMAND calendar.respond TARGET event_id ID key INPUT (response = 'accepted' | 'declined' | 'tentative')`
  records the connected account's response to an invitation.
- **move** — `EFFECT COMMAND calendar.move TARGET event_id ID key INPUT (destination = calendar_id)`
  moves the event to another calendar.

Both end `applied` once Calendar confirms the change; the invitation emails
that `send_updates` triggers are Calendar's own work and are not tracked.

## Setup

```json
"calendar": {
  "connector": "calendar",
  "credentials": {
    "service_account": {"env": "GOOGLE_SERVICE_ACCOUNT_JSON"},
    "delegate": "ops@acme.com"
  }
}
```

Share each calendar with the service account (see events to read, make
changes to write), or use domain-wide delegation with the `calendar.readonly`
or `calendar.events` scope and set `delegate`. Responding to an invitation
acts as the delegated account. On ActQL Cloud, hosted OAuth signs the account
in without a service account; the same scopes are requested.

## Capabilities and pushdown

| Operation | Pushed down when |
| --- | --- |
| Projection | Always after the complete declared Source row has been captured and validated; selecting fewer output columns does not hide malformed or incomplete input. |
| `WHERE` | Only predicates proven equivalent to the API request are removed from the residual. `timeMin` filters event end and `timeMax` filters event start, and the API ignores fractional request seconds; forwarding them alone is not exact SQL start/end pushdown. Likewise, `q` searches additional fields beyond summary/description. Keep the required Host residual; predicates on attendees, status and location run on the Host. |
| `ORDER BY`, `LIMIT` | `ORDER BY start` (ascending) with `LIMIT`; other orders run on the Host. |
| `AGGREGATE`, `JOIN` | Never; both run on the Host. |

`explain` shows the read with Site `connector:calendar` and Engine `Calendar
API`.

## Preview and reconciliation

**Preview.** Updates, upserts of an existing event, deletes, responses and
moves are `full_diff`: the Connector reads the event, records its current
fields and `etag`, and the Preview shows current and new values. The approved
version and change remain fixed. Updates and deletes use the documented
[`If-Match` condition](https://developers.google.com/workspace/calendar/api/guides/version-resources);
a failed condition makes the item `failed` with `conflict`. Continuing requires
a new Preview, not an automatic rebase or resend. A move must also honor its
approved version guard, but the update/delete documentation alone does not
qualify a conditional move contract. A backend without that contract must
refuse before dispatch; this is an implementation gap, not removal of the
required move operation. Inserts and upserts that create are `targeted`: the
Preview shows the full event that would be created and the calendar it goes to.

**Body-carrying writes.** Creates, updates and responses carry the original
request marker in the event's private extended properties in the same physical
write. Marker insertion is not a hidden earlier mutation. A lost create reply
can be reconciled by an authorized bounded lookup in the request's time window
for **that marker** and the approved values. Updates and responses use the same
original marker and approved values in their scoped readback. An equal summary,
time, changed `etag`, or values alone is not evidence of this operation.

**Native moves and deletes.** The documented
[`events.move`](https://developers.google.com/workspace/calendar/api/v3/reference/events/move)
and [`events.delete`](https://developers.google.com/workspace/calendar/api/v3/reference/events/delete)
requests have no body, so they cannot write a new private marker. Use those
native operations with the exact approved source event, calendar, destination
when applicable, notification choice and version guard. Do not replace delete
with a cancellation PATCH or silently PATCH a marker before moving or deleting.
A compound operation would need its own explicit Preview, complete operation
inventory, authority, capacity and disclosed atomicity.

**Confirmation and uncertain replies.** An authentic, retained response bound
to this same original physical request can confirm only its documented native
postcondition. A move requires the correlated complete Event response and the
approved destination/change; a delete requires its correlated native success
response, whose body is empty. A status number or detached response alone is
not such evidence. Any postcondition still requiring a readback needs an
explicitly authorized, funded read under the same operation owner. The existing
claim, current checks, apply receipt and physical cleanup remain separate.

After sending is possible, a missing, lost, partial or insufficient reply stays
`unknown` unless authentic evidence settles this exact operation. A later
missing event, cancellation, source tombstone, destination event, previous
marker or changed `etag` alone does not prove which write caused it. Google
does not guarantee private properties on
[deleted or moved-source tombstones](https://developers.google.com/workspace/calendar/api/v3/reference/events).
No marker is fabricated, no `OperationRef` is invented, and nothing is re-sent.

## Limits and cost

- Events in a time range are read 250 at a time; recurring events are
  expanded into instances, so a long range over a recurring series is many
  rows and counts against the Program's row limit.
- The API applies per-user and per-project quota units; the Connector paces
  within them and stops with an error, never a partial result, when the
  Program's row limit is reached.
- `send_updates = 'all'` sends an email per attendee per change; a Program
  that updates many events with it is bounded by the Effect's item limit, and
  the Preview says invitations would be sent.
- Free/busy queries cover at most the API's time-range limit per request;
  longer ranges are split.

## Example

Next week's customer meetings:

```sql
FROM calendar.events
|> WHERE calendar_id = 'sales@acme.com'
     AND start >= CURRENT_TIMESTAMP()
     AND start < TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
     AND status != 'cancelled'
|> SELECT start, summary, ARRAY_LENGTH(attendees) AS people
|> ORDER BY start;
```

Schedule a check-in for every high-risk account, once:

```sql
SELECT a.id, a.name, a.owner_email, risk.value.reason AS reason
FROM salesforce.accounts AS a
JOIN snowflake.usage_30d AS u ON a.id = u.account_id
|> INFER `model-task:churn-risk.v1`
     INPUT (notes = a.description, active_users = u.active_users, trend = u.trend) AS risk
|> WHERE risk.outcome = 'ok' AND risk.value.level = 'high'
|> EXTEND CONCAT('churn-checkin-', id, '@acme.com') AS ical_uid
|> EFFECT UPSERT calendar.events ID ical_uid
     SET (calendar_id = owner_email, summary = CONCAT('Check-in: ', name), description = reason,
          start = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 2 DAY),
          end = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 2 DAY) + INTERVAL 30 MINUTE);
```

Running it again updates the same events instead of creating new ones.

Decline every meeting that overlaps a planned absence:

```sql
FROM calendar.events
|> WHERE calendar_id = 'kim@acme.com'
     AND start >= @away_from AND start < @away_until
     AND status != 'cancelled'
|> EFFECT COMMAND calendar.respond TARGET id ID id INPUT (response = 'declined');
```
