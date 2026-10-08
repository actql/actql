import assert from 'node:assert/strict';

// Independent OTLP wire reader. Do not derive acceptance from SDK objects or
// the production serializer. Inputs are bounded test collector packets.
export function fields(input) {
  const result = [];
  let index = 0;
  const varint = () => {
    let value = 0n, shift = 0n;
    for (let n = 0; n < 10 && index < input.length; n++) {
      const byte = input[index++];
      value |= BigInt(byte & 127) << shift;
      if ((byte & 128) === 0) return value;
      shift += 7n;
    }
    throw new Error('InvalidFixtureProtobuf');
  };
  while (index < input.length) {
    const tag = Number(varint()), number = tag >> 3, wire = tag & 7;
    assert.ok(number > 0);
    let value;
    if (wire === 0) value = varint();
    else if (wire === 1 || wire === 5) {
      const size = wire === 1 ? 8 : 4;
      value = input.subarray(index, index + size); index += size;
    } else if (wire === 2) {
      const size = Number(varint());
      value = input.subarray(index, index + size); index += size;
    } else throw new Error('InvalidFixtureProtobuf');
    assert.ok(index <= input.length);
    result.push({number, value});
  }
  return result;
}
export const field = (input, number) => fields(input)
  .find(item => item.number === number)?.value;

export function records(packets, signal) {
  const result = [];
  for (const packet of packets.filter(item => item.path === `/v1/${signal}`)) {
    for (const resource of fields(packet.body).filter(item => item.number === 1)) {
      for (const scope of fields(resource.value).filter(item => item.number === 2)) {
        for (const record of fields(scope.value).filter(item => item.number === 2)) {
          result.push(record.value);
        }
      }
    }
  }
  return result;
}

export function attributes(record, number) {
  return Object.fromEntries(fields(record).filter(item => item.number === number)
    .map(item => {
      const key = field(item.value, 1).toString();
      const value = field(item.value, 2);
      const text = field(value, 1);
      return [key, text === undefined ? field(value, 3) : text.toString()];
    }));
}

export function assertNoMetricExemplars(packets) {
  let points = 0;
  for (const metric of records(packets, 'metrics')) {
    // OTLP Gauge/Sum, Histogram and ExponentialHistogram data points.
    for (const [kind, exemplar] of [[5, 5], [7, 5], [9, 10], [10, 11]]) {
      const data = field(metric, kind);
      if (data === undefined) continue;
      for (const point of fields(data).filter(item => item.number === 1)) {
        points++;
        assert.equal(field(point.value, exemplar), undefined);
      }
    }
  }
  assert.ok(points > 0, 'inspect actual exported metric data points');
}
