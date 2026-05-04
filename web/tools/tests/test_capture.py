"""Tests for capture_trace.py. Run with: cd web && python3 -m pytest tools/tests/ -v"""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import capture_trace as ct

FIXTURES = Path(__file__).parent / 'fixtures'


def test_parse_ppln_returns_list_of_cycle_snapshots():
    snapshots = ct.parse_ppln(FIXTURES / 'sample.ppln')
    assert isinstance(snapshots, list)
    assert all('cycle' in s for s in snapshots)
    assert snapshots[0]['cycle'] < snapshots[-1]['cycle']


def test_parse_out_extracts_committed_writebacks():
    wbs = ct.parse_out(FIXTURES / 'sample.out')
    assert isinstance(wbs, list)
    for w in wbs:
        assert 'reg' in w
        assert 'value' in w


def test_fallback_trace_from_out_only_produces_valid_snapshots():
    snapshots = ct.fallback_from_out(FIXTURES / 'sample.out')
    assert all('commit' in s for s in snapshots)
    assert all('cycle' in s for s in snapshots)


def test_detect_events_finds_mispredict():
    snaps = [
        {'cycle': 1, 'rob': [{'tag': 0, 'busy': True}, {'tag': 1, 'busy': True}, {'tag': 2, 'busy': True}], 'events': []},
        {'cycle': 2, 'rob': [{'tag': 0, 'busy': False}, {'tag': 1, 'busy': False}, {'tag': 2, 'busy': True}], 'events': []},
    ]
    out = ct.detect_events(snaps)
    assert any('mispredict' in e or 'flush' in e for e in out[1]['events'])
