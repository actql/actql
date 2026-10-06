import {formatSubmission, formatCancellation, formatReadFailure, formatEffectUncertainty,
  type OperationFormatOptions} from '@actql/sdk';
const options: OperationFormatOptions = {format: 'json', locale: 'ja', maxBytes: 65536};
for (const format of [formatSubmission, formatCancellation, formatReadFailure, formatEffectUncertainty]) {
  const value: string | undefined = format({}, options);
  void value;
}
// @ts-expect-error Display options cannot grant cancellation or execution permission.
formatCancellation({}, {format: 'html', confirmStop: true});
// @ts-expect-error No supported silent retry or read-resume option.
formatReadFailure({}, {format: 'json', retry: true});
