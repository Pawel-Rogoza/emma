"""Design checks: pip install jsonschema==4.25.1 pglast==7.7

Parses PostgreSQL DDL; does not execute a migration or verify pgvector at runtime.
"""
import json
from pathlib import Path

from jsonschema import Draft202012Validator
from pglast import parse_sql

root = Path(__file__).resolve().parent
schema = json.loads((root / 'retrieval.schema.json').read_text())
Draft202012Validator.check_schema(schema)
statements = parse_sql((root / 'schema.sql').read_text())


def validator(name):
    return Draft202012Validator(
        {'$ref': '#/$defs/' + name, '$defs': schema['$defs']},
        format_checker=Draft202012Validator.FORMAT_CHECKER,
    )


request = validator('request')
valid = {
    'query': 'Przedawnienie roszczeń', 'jurisdiction': 'PL',
    'asOf': '2026-09-22', 'kinds': ['legislation'],
}
request.validate(valid)
for key, value in [('limit', 9), ('asOf', '2026-02-30'),
                   ('tenantId', 'other'), ('jurisdiction', 'US')]:
    assert not request.is_valid({**valid, key: value}), (key, value)

result = validator('result')
empty = {
    'requestId': '00000000-0000-0000-0000-000000000001',
    'status': 'no_results', 'asOf': '2026-09-22',
    'corpusVersion': 'test-1', 'retrievalProfile': 'test-1',
    'passages': [], 'warnings': [], 'message': 'Brak źródeł', 'durationMs': 12,
}
result.validate(empty)
assert not result.is_valid({**empty, 'status': 'ok'})
assert not result.is_valid({**empty, 'status': 'unavailable', 'message': ''})
print(f'JSON Schema and boundary checks passed; {len(statements)} SQL statements parsed.')
