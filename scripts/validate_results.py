#!/usr/bin/env python3
"""Strict BehaviorSpace design/data audits; never repair or impute missing runs."""
import argparse
from collections import Counter
import csv
import itertools
import math
from pathlib import Path
import re
import shlex
import xml.etree.ElementTree as ET

FACTORS = ('missionary-effectiveness', 'royal-intolerance')
DEFAULTS = {'initial-missionaries': 12, 'initial-traders': 12,
            'trade-attractiveness': .6, 'tech-decay-rate': .015,
            'religion-trade-weight': .55, 'independence-effort': .15,
            'view-mode': 'kingdom'}
LEGACY_PARAMETERS = (*FACTORS, *DEFAULTS)
SETTINGS = '(list ' + ' '.join(LEGACY_PARAMETERS) + ')'
SEED = '100000 + behaviorspace-run-number'
METRICS = ['control-fraction', 'cumulative-trade-profit', 'controlled-planets',
           'controlled-kingdoms', 'mean-religion', 'mean-dependency',
           'total-executed-missionaries', 'total-executed-traders',
           'foundation-treasury', 'recruitment-costs', 'total-successful-trades',
           'ticks', 'model-valid?', 'netlogo-version', SEED, SETTINGS]
NAME = 'Foundation Religious-Economic Tipping Point'
DURATION_NAMES = {'Foundation Baseline Sweep (450 ticks)': 450,
                  'Foundation Extended Sweep (1000 ticks)': 1000}
DURATION_METRICS = [*METRICS[:12], 'active-tick-limit', *METRICS[12:15]]

def require(condition, message):
    if not condition:
        raise ValueError(message)

def scalar(value):
    if value.startswith('"'):
        return value.strip('"')
    try:
        return float(value)
    except ValueError:
        return value

def design(path, name=None, production=False):
    root = ET.parse(path).getroot()
    choices = [e for e in root.findall('experiment') if name is None or e.get('name') == name]
    require(len(choices) == 1, 'Expected exactly one matching experiment')
    e = choices[0]
    grid = {}
    for node in e.findall('enumeratedValueSet'):
        key = node.get('variable')
        require(key not in grid, 'Duplicate parameter')
        grid[key] = [scalar(v.get('value')) for v in node.findall('value')]
        require(len(set(grid[key])) == len(grid[key]) > 0, 'Empty/duplicate values')
    duration_design = 'tick-limit' in grid
    parameters = (*LEGACY_PARAMETERS, 'tick-limit') if duration_design else LEGACY_PARAMETERS
    require(set(grid) == set(parameters), 'Missing/extra parameters')
    require(not e.findall('steppedValueSet') and not e.findall('subExperiment'), 'Use explicit enumerated design')
    for key, value in DEFAULTS.items():
        require(grid[key] == [value], f'Fixed default changed: {key}')
    metrics = DURATION_METRICS if duration_design else METRICS
    require([m.text for m in e.findall('metric')] == metrics, 'Wrong reporters')
    require(e.findtext('setup') == 'random-seed (100000 + behaviorspace-run-number) setup', 'Wrong seed/setup scheme')
    require(e.findtext('go') in ('go', 'go assert-valid-model-state'), 'Unexpected go command')
    repeats = int(e.get('repetitions'))
    limit_node = e.find('timeLimit')
    time_limit = None if limit_node is None else int(limit_node.get('steps'))
    if duration_design:
        require(len(grid['tick-limit']) == 1, 'Duration must be fixed per experiment')
        horizon = int(grid['tick-limit'][0])
        require(time_limit == horizon and 100 <= horizon <= 3000,
                'BehaviorSpace time limit must match the explicit model horizon')
        require(e.findtext('exitCondition') == 'ticks >= active-tick-limit',
                'Duration sweep exit condition must match the captured horizon')
    else:
        horizon = time_limit
        require(0 < horizon <= 450, 'Invalid legacy horizon')
    require(repeats > 0, 'Invalid repetitions')
    if production:
        require(e.get('name') == NAME or DURATION_NAMES.get(e.get('name')) == horizon,
                'Wrong production experiment name')
        require(repeats == 20 and horizon in (450, 1000), 'Wrong production design')
        require(e.get('runMetricsEveryStep') == 'false', 'Production must export end states')
        require(grid[FACTORS[0]] == [.1,.15,.2,.25,.3,.35,.4], 'Unapproved effectiveness grid')
        require(grid[FACTORS[1]] == [.2,.3,.4,.5,.6,.7,.8], 'Unapproved intolerance grid')
    return e, grid, repeats, horizon

def read_table(path, name):
    with Path(path).open(newline='', encoding='utf-8-sig') as f:
        rows = list(csv.reader(f))
    indices = [i for i,r in enumerate(rows) if r and r[0] == '[run number]']
    require(len(indices) == 1, 'Missing/duplicate BehaviorSpace header')
    i = indices[0]
    require([name] in rows[:i], 'Wrong experiment metadata')
    require(any('NetLogo 6.4.' in x for r in rows[:i] for x in r), 'Wrong runtime metadata')
    header = rows[i]
    require(len(set(header)) == len(header), 'Duplicate columns')
    data = []
    for r in rows[i+1:]:
        if not r:
            continue
        require(len(r) == len(header), 'Malformed/truncated row')
        data.append(dict(zip(header,r)))
    require(bool(data), 'No data')
    return header, data

def audit_row(row, expected, seed, step, metrics, horizon):
    require(row['model-valid?'] == 'true', 'Invalid model state')
    require(re.fullmatch(r'6\.4\.\d+', row['netlogo-version'].strip('"')), 'Wrong NetLogo version')
    values = {}
    for key in metrics:
        if key in ('model-valid?', 'netlogo-version', SETTINGS):
            continue
        value = float(row[key])
        require(math.isfinite(value), f'Nonfinite {key}')
        values[key] = value
    require(values['ticks'] == step, 'Tick/step mismatch')
    if 'active-tick-limit' in values:
        require(values['active-tick-limit'] == horizon, 'Wrong captured duration')
    require(values[SEED] == seed, 'Incorrect seed')
    if SETTINGS in row:
        actual = shlex.split(row[SETTINGS].strip('[]'))
        want = [expected[k] for k in LEGACY_PARAMETERS]
        require(len(actual) == len(want), 'Wrong settings metric')
        require(all((a == b if isinstance(b,str) else float(a) == b) for a,b in zip(actual,want)), 'Setup changed parameters')
    for key in ('control-fraction','mean-religion','mean-dependency'):
        require(0 <= values[key] <= 1, f'Out of bounds: {key}')
    for key in ('controlled-planets','controlled-kingdoms','total-executed-missionaries',
                'total-executed-traders','total-successful-trades','recruitment-costs'):
        require(values[key] >= 0 and values[key].is_integer(), f'Invalid count: {key}')
    require(values['controlled-planets'] <= 30 and values['controlled-kingdoms'] <= 4, 'Control count out of bounds')
    require(abs(values['control-fraction'] - values['controlled-planets']/30) < 1e-12, 'Incorrect control reporter')
    require(values['foundation-treasury'] >= 0 and abs(values['foundation-treasury'] - 200 - values['cumulative-trade-profit']) < 1e-8, 'Incorrect profit/treasury identity')

def validate(path, xml, name=None, production=False, log_path=None):
    e, grid, repeats, horizon = design(xml, name, production)
    header, data = read_table(path,e.get('name'))
    parameters = tuple(grid)
    metrics = DURATION_METRICS if 'tick-limit' in grid else METRICS
    require(set(header) == {'[run number]','[step]',*parameters,*metrics}, 'Unexpected columns')
    # NetLogo enumerates parameter products in XML order, repetitions innermost.
    configs = list(itertools.product(*grid.values()))
    planned = {i*repeats+r+1: dict(zip(grid,c)) for i,c in enumerate(configs) for r in range(repeats)}
    steps = range(horizon+1) if e.get('runMetricsEveryStep') == 'true' else [horizon]
    observed = {}
    for row in data:
        run,step = int(row['[run number]']),int(row['[step]'])
        require(run in planned, 'Unexpected run ID')
        require((run,step) not in observed, 'Duplicate run/step')
        require(all(scalar(row[k]) == v for k,v in planned[run].items()), 'Wrong parameter/run mapping')
        audit_row(row, planned[run], 100000+run,step,metrics,horizon)
        observed[run,step] = row
    require(set(observed) == {(r,s) for r in planned for s in steps}, 'Incomplete run/step coverage')
    terminal = [observed[r,horizon] for r in planned]
    counts = Counter((float(r[FACTORS[0]]),float(r[FACTORS[1]])) for r in terminal)
    require(all(n == repeats for n in counts.values()), 'Incorrect per-cell repetitions')
    message = (f'PASS: {e.get("name")}: {len(terminal)} runs, {len(counts)} cells x '
               f'{repeats}, {len(data)} rows; seeds 100001–{100000+len(terminal)}, '
               f'tick {horizon}')
    print(message)
    if log_path is not None:
        Path(log_path).write_text(message + '\n', encoding='utf-8')
    return terminal

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('csv',type=Path); p.add_argument('xml',type=Path)
    p.add_argument('--name'); p.add_argument('--production',action='store_true')
    p.add_argument('--log',type=Path)
    a=p.parse_args()
    try: validate(a.csv,a.xml,a.name,a.production,a.log)
    except (ValueError,KeyError,OSError,ET.ParseError) as e: raise SystemExit(f'FAIL: {e}')
