// Original Gmail list/get rejection bounds. These immutable DATA checks issue
// neither reader capacity nor Account/Site permission.
const positiveLimits = ['maxResponseBytes', 'maxTotalResponseBytes', 'maxNodes', 'maxDepth',
  'pageSize', 'maxPages', 'maxMailboxBytes', 'maxTargetBytes', 'maxIdBytes', 'maxTokenBytes',
  'maxValueNodes', 'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'] as const;
const nonnegativeLimits = ['maxThreads', 'maxMessages', 'maxLabels', 'maxHeaders',
  'maxHeaderUnits', 'maxCommentDepth', 'maxValueTextBytes'] as const;
type GmailLimitName = (typeof positiveLimits)[number] | (typeof nonnegativeLimits)[number];
type GmailLimitFields = Readonly<Partial<Record<GmailLimitName, unknown>>>;
type GmailThreadReaderLimits = Readonly<Record<GmailLimitName, number>>;

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const integer = (value: unknown): value is number =>
  Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 2147483647;

export const gmailThreadReaderLimitNames = Object.freeze([...positiveLimits, ...nonnegativeLimits]);

export function gmailThreadReaderLimitsValid(limits: GmailLimitFields | null | undefined): limits is GmailThreadReaderLimits {
  return limits !== null && typeof limits === 'object' &&
    positiveLimits.every(name => integer(limits[name]) && (limits[name] as number) > 0) &&
    nonnegativeLimits.every(name => integer(limits[name])) && (limits.pageSize as number) <= 500 &&
    (limits.maxPages as number) <= 2147483647 - (limits.maxThreads as number);
}

export function checkGmailThreadReaderLimits(limits: GmailLimitFields | null | undefined) {
  const bounded = Object.freeze({...limits});
  if (!gmailThreadReaderLimitsValid(bounded)) fail('InvalidGmailThreadReaderFactory');
  return bounded;
}
