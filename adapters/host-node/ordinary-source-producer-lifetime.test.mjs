import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';

test('ordinary producers have no cumulative lifetime issuance limit after completed requests', async () => {
  const originals = Object.freeze({});
  const first = await prepareOrdinarySourceManagedInstallation(originals, {validator() {}}, false);
  const second = await prepareOrdinarySourceManagedInstallation(Object.freeze({}), {validator() {}}, false);
  let last;
  for (let index = 0; index < 4098; index++) {
    const receipt = first.beforeSourceSnapshot('aql', 'SELECT 1');
    const body = Object.freeze({index});
    const request = Object.freeze({index});
    first.bindSourceSnapshot(receipt, body);
    first.bindSourceRequest(receipt, body, request);
    first.finishSourceProducer(receipt, index % 2 === 0 ? 'returned' : 'failed');
    last = receipt;
  }
  assert.throws(() => second.bindSourceSnapshot(last, {}), {code: 'ForeignInstalledSourceProducer'});
  assert.throws(() => first.bindSourceSnapshot(Object.freeze({}), {}), {code: 'ForeignInstalledSourceProducer'});
  const next = first.beforeSourceSnapshot('aql', 'SELECT 2');
  first.finishSourceProducer(next, 'returned');
  assert.deepEqual(await first.close(), {pending: false});
  assert.throws(() => first.beforeSourceSnapshot('aql', 'SELECT 3'), {code: 'SourceManagedPreparationUnavailable'});
  const independent = second.beforeSourceSnapshot('aql', 'SELECT 4');
  second.finishSourceProducer(independent, 'returned');
  assert.deepEqual(await second.close(), {pending: false});
});

// Actual manager identity/lifetime operations, without semantic compilation or
// a physical Source. These cases do not establish normal Request funding.
async function producerIndexFixture(validate = () => {}) {
  const view = await prepareOrdinarySourceManagedInstallation(Object.freeze({}),
    {validator: validate}, false);
  const records = [];
  return {
    view,
    begin(request = Object.freeze({})) {
      const receipt = view.beforeSourceSnapshot('aql', 'SELECT 1');
      const body = Object.freeze({});
      view.bindSourceSnapshot(receipt, body);
      const record = {receipt, body, request};
      records.push(record);
      return record;
    },
    bind(record, request = record.request) {
      view.bindSourceRequest(record.receipt, record.body, request);
    },
    async close() {
      for (const record of records) view.finishSourceProducer(record.receipt, 'returned');
      assert.deepEqual(await view.close(), {pending: false});
    },
  };
}

test('producer request index preserves exact live identity and separate Host ownership', async () => {
  const first = await producerIndexFixture(), other = await producerIndexFixture();
  try {
    const record = first.begin(Object.freeze({original: true}));
    first.bind(record);
    assert.equal(first.view.submittedIntentOriginal(record.request), undefined);
    for (const value of [{...record.request}, Object.freeze({}), undefined, null]) {
      assert.throws(() => first.view.submittedIntentOriginal(value),
        {code: 'ForeignInstalledSourceProducer'});
    }
    assert.throws(() => other.view.submittedIntentOriginal(record.request),
      {code: 'ForeignInstalledSourceProducer'});
    assert.equal(first.view.submittedIntentOriginal(record.request), undefined);
  } finally {await first.close(); await other.close();}
});

test('producer request index refuses rebinding a live or retired original without poisoning another receipt', async () => {
  const f = await producerIndexFixture();
  try {
    const original = f.begin(), sibling = f.begin();
    f.bind(original);
    assert.throws(() => f.bind(sibling, original.request),
      {code: 'ForeignInstalledSourceProducer'});
    f.bind(sibling);
    f.view.finishSourceProducer(original.receipt, 'failed');
    assert.throws(() => f.view.submittedIntentOriginal(original.request),
      {code: 'ForeignInstalledSourceProducer'});
    const later = f.begin();
    assert.throws(() => f.bind(later, original.request),
      {code: 'ForeignInstalledSourceProducer'});
    f.bind(later);
    assert.equal(f.view.submittedIntentOriginal(sibling.request), undefined);
    assert.equal(f.view.submittedIntentOriginal(later.request), undefined);
  } finally {await f.close();}
});

test('producer request index keeps current and synchronous retirement fences', async () => {
  let onCurrent;
  const f = await producerIndexFixture(() => onCurrent?.());
  try {
    const record = f.begin(); f.bind(record);
    const refusal = Object.freeze(new Error('OriginalCurrentRefusal'));
    onCurrent = () => {throw refusal;};
    assert.throws(() => f.view.submittedIntentOriginal(record.request), error => error === refusal);
    onCurrent = () => {
      onCurrent = undefined;
      f.view.finishSourceProducer(record.receipt, 'returned');
    };
    assert.throws(() => f.view.submittedIntentOriginal(record.request),
      {code: 'ForeignInstalledSourceProducer'});
    onCurrent = undefined;
    await f.close();
    assert.throws(() => f.view.submittedIntentOriginal(record.request),
      {code: 'SourceManagedPreparationUnavailable'});
  } finally {onCurrent = undefined; await f.close();}
});

test('producer request index refuses synchronous Host close during the current callback', async () => {
  let onCurrent, closing;
  const f = await producerIndexFixture(() => onCurrent?.());
  try {
    const record = f.begin(); f.bind(record);
    onCurrent = () => {
      onCurrent = undefined;
      closing = f.view.close();
    };
    assert.throws(() => f.view.submittedIntentOriginal(record.request),
      {code: 'ForeignInstalledSourceProducer'});
    assert.deepEqual(await closing, {pending: true}, 'Request stop is not completed cleanup');
  } finally {
    onCurrent = undefined;
    if (closing !== undefined) await closing;
    await f.close();
  }
});

test('producer request index performs direct membership lookups at N and 2N live requests', async t => {
  const measurements = [];
  for (const count of [16, 32]) {
    const f = await producerIndexFixture();
    try {
      const records = Array.from({length: count}, () => f.begin());
      for (const record of records) f.bind(record);
      const iterate = Set.prototype[Symbol.iterator], has = Set.prototype.has;
      let visits = 0, membershipChecks = 0;
      try {
        Set.prototype[Symbol.iterator] = function () {
          const iterator = Reflect.apply(iterate, this, []);
          return {
            next() {
              const item = iterator.next();
              if (!item.done) visits++;
              return item;
            },
            [Symbol.iterator]() {return this;},
          };
        };
        Set.prototype.has = function (value) {
          membershipChecks++;
          return Reflect.apply(has, this, [value]);
        };
        // This synchronous window invokes the actual manager lookup, not a
        // replacement resolver. Restore observers before assertions/cleanup.
        for (const record of records) f.view.submittedIntentOriginal(record.request);
      } finally {
        Set.prototype[Symbol.iterator] = iterate;
        Set.prototype.has = has;
      }
      measurements.push({count, visits, membershipChecks});
    } finally {await f.close();}
  }
  t.diagnostic(JSON.stringify({scope: 'actual manager lookup work, not latency', measurements}));
  for (const {count, visits, membershipChecks} of measurements) {
    assert.equal(visits, 0, 'Request lookup must not scan the live cleanup inventory');
    assert.equal(membershipChecks, count, 'One direct membership check per exact original');
  }
});
