// Original Gmail list/get rejection bounds. These immutable DATA checks issue
// neither reader capacity nor Account/Site permission.
const positiveLimits = ['maxResponseBytes', 'maxTotalResponseBytes', 'maxNodes', 'maxDepth',
  'pageSize', 'maxPages', 'maxMailboxBytes', 'maxTargetBytes', 'maxIdBytes', 'maxTokenBytes',
  'maxValueNodes', 'maxRowsWireBytes', 'maxRowsWireNodes', 'maxRowsWireDepth'];
const nonnegativeLimits = ['maxThreads', 'maxMessages', 'maxLabels', 'maxHeaders',
  'maxHeaderUnits', 'maxCommentDepth', 'maxValueTextBytes'];
const fail = code => {throw Object.assign(new Error(code), {code});};
const integer = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;

export const gmailThreadReaderLimitNames = Object.freeze([...positiveLimits, ...nonnegativeLimits]);

export function gmailThreadReaderLimitsValid(limits) {
  return limits !== null && typeof limits === 'object' &&
    positiveLimits.every(name => integer(limits[name]) && limits[name] > 0) &&
    nonnegativeLimits.every(name => integer(limits[name])) && limits.pageSize <= 500 &&
    limits.maxPages <= 2147483647 - limits.maxThreads;
}

export function checkGmailThreadReaderLimits(limits) {
  const bounded = Object.freeze({...limits});
  if (!gmailThreadReaderLimitsValid(bounded)) fail('InvalidGmailThreadReaderFactory');
  return bounded;
}
