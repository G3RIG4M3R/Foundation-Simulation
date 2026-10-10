#!/usr/bin/env python3
"""Audit NetLogo widgets and real plot exports; compare plotted and unplotted runs."""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
from xml.sax.saxutils import escape

from check_model import test_model_source

SLIDERS = {
    'initial-missionaries': (0, 40, 12, 2),
    'missionary-effectiveness': (0, .5, .25, .05),
    'initial-traders': (0, 40, 12, 2),
    'trade-attractiveness': (0, 1, .6, .05),
    'royal-intolerance': (0, 1, .5, .05),
    'tech-decay-rate': (0, .04, .015, .005),
    'religion-trade-weight': (0, .8, .55, .05),
    'independence-effort': (0, 1, .15, .05),
    'tick-limit': (0, 3000, 0, 50),
}
PLOTS = ('Control over time', 'Religion and dependency', 'Religion distribution', 'Trade economy')
METRICS = ('ticks', 'model-valid?', 'trade-trace', 'controlled-planets', 'mean-religion',
           'mean-dependency', 'trade-income-this-tick', 'netlogo-version')


def widgets(root):
    sections = (root / 'model/foundation.nlogo').read_text().split('@#$#@#$#@')
    blocks = [block.splitlines() for block in sections[1].strip().split('\n\n')]
    sliders = {row[6]: row for row in blocks if row[0] == 'SLIDER'}
    assert sliders.keys() == SLIDERS.keys(), 'Slider names/count'
    for name, expected in SLIDERS.items():
        row = sliders[name]
        # GUI and headless loaders differ if the two serialized name fields disagree.
        assert row[5] == row[6] and tuple(map(float, row[7:11])) == expected, name
    chooser = [row for row in blocks if row[0] == 'CHOOSER']
    assert len(chooser) == 1 and chooser[0][5:9] == [
        'view-mode', 'view-mode', '"kingdom" "religion" "dependency" "control"', '0']
    buttons = {row[5]: row for row in blocks if row[0] == 'BUTTON'}
    for name in ('setup', 'go-once', 'go'):
        assert buttons[name][6] == name
        assert buttons[name][7] == ('T' if name == 'go' else 'NIL')
    assert buttons['refresh view'][6:8] == ['update-appearance', 'NIL']
    # Quoted strings are backslash-escaped in the serialized Interface section;
    # BehaviorSpace metrics require executable NetLogo source.
    monitors = [row[6].replace('\\"', '"') for row in blocks if row[0] == 'MONITOR']
    assert {'ticks', 'controlled-planets', 'controlled-kingdoms', 'mean-religion',
            'mean-dependency', 'foundation-treasury', 'count trade-routes',
            'total-executed-missionaries + total-executed-traders'} <= set(monitors)
    plots = [row for row in blocks if row[0] == 'PLOT']
    assert tuple(row[5] for row in plots) == PLOTS
    assert all('PENS' in row for row in plots)
    for section in ('WHAT IS IT?', 'HOW TO USE IT', 'HOW IT WORKS', 'THINGS TO NOTICE / TRY',
                    'SIMPLIFICATIONS AND LIMITATIONS', 'EXTENDING THE MODEL', 'CREDITS / REFERENCES'):
        assert '## ' + section in sections[2]
    # All production monitors must compile and evaluate in the real runtime too.
    print('PASS S6-A/F structure: 9 exact sliders, chooser, core buttons, pure refresh, 12 monitors, 4 plots, ODD sections')
    return monitors


def table(path):
    with path.open(newline='') as stream:
        rows = list(csv.reader(stream))
    index = next(i for i, row in enumerate(rows) if row and row[0] == '[run number]')
    assert ['Interface observation'] in rows[:index]
    header = rows[index]
    records = []
    for row in rows[index + 1:]:
        if row:
            assert len(row) == len(header)
            records.append(dict(zip(header, row)))
    assert len(records) == 451
    for step, row in enumerate(records):
        assert row['[run number]'] == '1' and int(row['[step]']) == step
        assert float(row['ticks']) == step and row['model-valid?'] == 'true'
        assert row['netlogo-version'].strip('"') == '6.4.0'
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlogo_home', type=Path)
    parser.add_argument('output_directory', type=Path, help='Fresh directory for measured evidence')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    monitors = widgets(root)
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=False)
    launcher = args.netlogo_home.resolve() / 'NetLogo_Console'
    cases = ('plots-on', 'views-changing', 'plots-off')
    traces = {}
    with tempfile.TemporaryDirectory(prefix='foundation-interface-') as directory:
        model = Path(directory) / 'foundation.nlogo'
        model.write_text(test_model_source(root, 6))
        for case in cases:
            destination = output / case
            destination.mkdir()
            commands = 'go assert-valid-model-state'
            if case == 'views-changing':
                commands = 'set view-mode item (ticks mod 4) ["kingdom" "religion" "dependency" "control"] update-appearance ' + commands
            exports = ''
            if case != 'plots-off':
                exports = ' '.join(f'export-plot {json.dumps(title)} {json.dumps(str(destination / (str(i) + ".csv")))}'
                                   for i, title in enumerate(PLOTS))
                exports += f' setup ask planets with [not foundation?] [set religion 1 set tech-dependency 1 set trade-trust 1 set hostility 0] repeat 5 [go] export-plot "Control over time" {json.dumps(str(destination / "control-fixture.csv"))}'
                exports += f' interface-histogram-fixture export-plot "Religion distribution" {json.dumps(str(destination / "boundaries.csv"))}'
                exports += ' setup ' + ' '.join(f'export-plot {json.dumps(title)} {json.dumps(str(destination / ("reset-" + str(i) + ".csv")))}'
                                               for i, title in enumerate(PLOTS))
            metrics = '\n'.join(f'<metric>{escape(name)}</metric>' for name in dict.fromkeys((*METRICS, *monitors)))
            xml = destination / 'interface.xml'
            xml.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE experiments SYSTEM "behaviorspace.dtd">
<experiments><experiment name="Interface observation" repetitions="1" runMetricsEveryStep="true">
<setup>set tick-limit 450 trade-fixture 12 12 123</setup>
<go>{escape(commands)}</go>
{('<postRun>' + escape(exports) + '</postRun>') if exports else ''}
<timeLimit steps="450"/>
{metrics}
</experiment></experiments>
''')
            command = [str(launcher), '--headless', '--model', str(model), '--setup-file', str(xml),
                       '--experiment', 'Interface observation', '--threads', '1', '--table', str(destination / 'trace.csv')]
            if case != 'plots-off':
                command.append('--update-plots')
            result = subprocess.run(command, capture_output=True, text=True, timeout=240)
            if result.returncode or 'RUNTIME ERROR' in result.stdout + result.stderr:
                raise ValueError(result.stdout + result.stderr)
            traces[case] = table(destination / 'trace.csv')
            print('PASS real-runtime trace:', case, flush=True)
    assert traces['plots-on'] == traces['views-changing'] == traces['plots-off'], 'Charts/view changes altered simulation traces'
    audit_plots(output, traces)
    paths = [root / 'model/foundation.nlogo', Path(__file__).resolve(), root / 'tests/stage6_checks.nls',
             *sorted(output.rglob('*.csv')), *sorted(output.rglob('*.xml'))]
    (output / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path}\n' for path in paths))
    print('PASS S6-C/E: plotted/unplotted/view-changing traces identical; actual chart points, histogram boundaries and plot reset audited')
    print('GUI behavior and screenshot review are separate from these headless checks.')


def audit_plots(output, traces):
    for case in ('plots-on', 'views-changing'):
        destination = output / case
        records = traces[case]
        for index, title in enumerate(PLOTS):
            bounds, pens = read_plot(destination / f'{index}.csv', title)
            assert bounds['x min'] == 0 and bounds['x max'] == (1 if index == 2 else 450)
            if index == 2:
                points = pens['worlds']
                assert sum(y for x, y in points) == 30
                assert all(0 <= x < 1 and y >= 0 and y == int(y) for x, y in points)
            else:
                for pen, points in pens.items():
                    metric = 'trade-income-this-tick' if index == 3 else pen
                    assert points == [(float(step), float(row[metric])) for step, row in enumerate(records)], (case, title, pen)
                if index == 1:
                    assert bounds['y min'] == 0 and bounds['y max'] == 1
                    assert len(set(y for x, y in pens['mean-religion'])) > 1
                if index == 3:
                    assert any(y > 0 for x, y in pens['gross trade income']), 'No observed sales in chart'
                    assert bounds['y max'] >= max(y for x, y in pens['gross trade income'])
            _, reset = read_plot(destination / f'reset-{index}.csv', title)
            if index == 2:
                assert sum(y for x, y in reset['worlds']) == 30, 'Histogram did not reset'
            else:
                assert all(len(points) == 1 and points[0][0] == 0 for points in reset.values()), 'Time series retained earlier run'
                if index in (0, 3):
                    assert all(points[0][1] == 0 for points in reset.values())
        _, boundary = read_plot(destination / 'boundaries.csv', 'Religion distribution')
        assert boundary['worlds'] == [(0.0, 10.0), (0.5, 10.0), (0.9, 10.0)], 'Histogram lost upper boundary or accumulated old bins'
        _, controlled = read_plot(destination / 'control-fixture.csv', 'Control over time')
        assert controlled['controlled-planets'] == [(float(i), 0.0) for i in range(5)] + [(5.0, 30.0)], 'Control plot does not reflect real five-tick control'


def read_plot(path, title):
    with path.open(newline='') as stream:
        rows = list(csv.reader(stream))
    assert rows[0] == ['export-plot data (NetLogo 6.4.0)']
    assert [f'"{title}"'] in rows
    meta = next(i for i, row in enumerate(rows) if row and row[0] == 'x min')
    bounds = {name: float(value) for name, value in zip(rows[meta][:4], rows[meta + 1][:4])}
    start = next(i for i, row in enumerate(rows) if row and row[:4] == ['x', 'y', 'color', 'pen down?'])
    names = [value.strip('"') for value in rows[start - 1][::4]]
    assert len(names) == len(set(names))
    pens = {name: [] for name in names}
    for row in rows[start + 1:]:
        if not row:
            continue
        assert len(row) == 4 * len(names)
        for i, name in enumerate(names):
            x, y, color, down = row[4 * i:4 * i + 4]
            if x == '' and y == '':
                continue
            x, y = float(x), float(y)
            assert math.isfinite(x) and math.isfinite(y) and down == 'true'
            pens[name].append((x, y))
    assert all(pens.values()), f'Empty plot: {path}'
    return bounds, pens


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, ValueError, StopIteration, KeyError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f'FAIL: {error}') from error
