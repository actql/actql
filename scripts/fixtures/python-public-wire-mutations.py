"""Meaningful mutation probes over generated Remote codec bytes, never new expectations."""
import json
from pathlib import Path
import sys
import types

root=Path(sys.argv[1]).resolve()
sys.path.insert(0,str(root/'packages/python-sdk/src'))
from actql_sdk import _wire_codec

vectors={entry['name']:entry for entry in json.load(sys.stdin)}
source=Path(_wire_codec.__file__).read_text()
mutations=[
 ('negative zero','not _finite_number(value)','False','admission revision negative decimal zero','admission'),
 ('integer range','abs(value) <= SAFE_INTEGER and ','','admission revision unsafe integer','admission'),
 ('integer fraction','and int(value) == value','','admission revision fraction','admission'),
 ('UTF-16 maximum','length = utf16_length(value)','length = len(value)','profile scope astral258','profile'),
 ('NULL/omission',"return type(value) is str","return value is None or type(value) is str",'held optional field null','held'),
 ('unknown variant',"'oneOf' in schema and sum(valid(value, rule) for rule in schema['oneOf']) != 1",'False','report unknown variant','check_outcome'),
 ('correlation','value[field] == request_id','True','held wrong identity','held'),
 ('old revision',"value['outcome_schema_cid'] != CONTRACT['check_outcome_schema_cid']",'False','report old outcome CID','check_outcome'),
 ('input revision',"(doc['revision'], doc['kind']) != (location['revision'], location['kind'])", "doc['kind'] != location['kind']",'report foreign input revision','check_outcome'),
 ('ECMAScript whitespace','not _pattern_matches(schema[\'pattern\'], value)',"re.search(schema['pattern'], value, re.ASCII) is None",'report canonical field NBSP','check_outcome'),
]
for name,before,after,probe,kind in mutations:
    assert source.count(before)==1,(name,'mutation site')
    module=types.ModuleType('actql_sdk._wire_mutant')
    module.__package__='actql_sdk'
    module.__file__=_wire_codec.__file__
    exec(compile(source.replace(before,after),'<wire-mutant>','exec'),module.__dict__)
    entry=vectors[probe]
    value=json.loads(entry['valueJSON'])
    assert entry['expected'] is False
    if kind in ('profile','admission'):
        actual=module.valid(value,kind)
    elif kind=='held':
        actual=module.correlated(value,'held',entry['requestId'])
    else:
        actual=module.check_outcome(value)
    assert actual is True,(name,'mutant did not expose the targeted prohibited acceptance')
print(json.dumps({'killed':len(mutations),'survived':0}))
