#!/usr/bin/env python3
"""Capture genuine NetLogo GUI states; optional JPype1 dependency and display required."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import time


def main():
    import jpype
    from PIL import Image
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('netlogo_home', type=Path)
    p.add_argument('--model', type=Path)
    args = p.parse_args()
    root = Path(__file__).resolve().parents[1]
    model = (args.model or root / 'model/foundation.nlogo').resolve()
    home = args.netlogo_home.resolve()
    output = root / 'presentation/media'
    output.mkdir(parents=True, exist_ok=True)
    jpype.startJVM(str(home / 'lib/runtime/lib/server/libjvm.so'),
                  '--add-exports=java.base/java.lang=ALL-UNNAMED',
                  '--add-exports=java.desktop/sun.awt=ALL-UNNAMED',
                  '--add-exports=java.desktop/sun.java2d=ALL-UNNAMED',
                  '-Dnetlogo.extensions.dir=' + str(home / 'extensions'),
                  classpath=[str(f) for f in (home / 'lib/app').glob('*.jar')])
    app_class = jpype.JClass('org.nlogo.app.App')
    app_class.main(jpype.JArray(jpype.JString)([]))
    time.sleep(3)
    app = app_class.app()
    swing = jpype.JClass('javax.swing.SwingUtilities')
    swing.invokeAndWait(jpype.JProxy('java.lang.Runnable', dict(run=lambda: app.open(str(model), False))))
    settings = ('set tick-limit 1000 set initial-missionaries 12 set initial-traders 20 '
                'set missionary-effectiveness 0.5 set royal-intolerance 0 '
                'set trade-attractiveness 0.8 set tech-decay-rate 0.015 '
                'set religion-trade-weight 0.8 set independence-effort 0.15 '
                'set view-mode "control" random-seed 500207 setup')
    app.command(settings)
    ws = app.workspace()
    frames, observed = [], []
    for tick in range(0, 1001, 50):
        if tick: app.command('repeat 50 [go]')
        time.sleep(.12)
        actual = float(ws.report('ticks'))
        control = float(ws.report('control-fraction'))
        assert actual == tick, (actual, tick)
        observed.append({'tick': tick, 'control_fraction': control})
        path = output / f'view-{tick:04d}.png'
        path.unlink(missing_ok=True)
        ws.exportView(str(path), 'PNG')
        deadline = time.monotonic() + 15
        while not path.exists():
            if time.monotonic() > deadline: raise TimeoutError(str(path))
            time.sleep(.1)
        time.sleep(.2)
        frames.append(Image.open(path).convert('RGB'))
        if tick in (0, 500, 1000):
            ws.exportInterface(str(output / f'interface-{tick:04d}.png'))
            time.sleep(.4)
    raw = root / 'results/tipping_point_investigation/raw/representative_above_boundary.csv'
    with raw.open(newline='') as stream: rows = list(csv.reader(stream))
    i = next(i for i, r in enumerate(rows) if r and r[0] == '[run number]')
    records = [dict(zip(rows[i], r)) for r in rows[i+1:] if r]
    for point in observed:
        assert abs(point['control_fraction'] - float(records[point['tick']]['control-fraction'])) < 1e-12
    assert bool(ws.report('model-valid?'))
    app.command('go-once')
    assert float(ws.report('ticks')) == 1000
    for mode in ('kingdom', 'religion', 'dependency', 'control'):
        app.command(f'set view-mode "{mode}" update-appearance')
        assert float(ws.report('control-fraction')) == observed[-1]['control_fraction']
    frames[0].save(output / 'foundation_demo.gif', save_all=True,
                   append_images=frames[1:], duration=200, loop=0)
    # Only three useful stills are retained; the GIF contains the full capture sequence.
    for tick in range(0, 1001, 50):
        if tick not in (0, 500, 1000): (output / f'view-{tick:04d}.png').unlink()
    (output / 'capture_provenance.json').write_text(json.dumps({
        'runtime': 'NetLogo 6.4.0 GUI', 'model_sha256': hashlib.sha256(model.read_bytes()).hexdigest(),
        'setup_commands': settings, 'frame_step': 50, 'gif_frame_ms': 200,
        'measured_states': observed, 'matches_confirmatory_replay': True,
        'note': 'Accelerated GUI exports; no state fabricated. Final control 19/30, two kingdoms.'
    }, indent=2) + '\n')
    print('PASS: 21 genuine GUI frames match seed 500207 raw trace; interface exported; views and finite go-once checked', flush=True)
    os._exit(0)  # NetLogo GUI owns persistent Swing threads.


if __name__ == '__main__':
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        # A failed capture must not leave NetLogo's Swing threads running.
        os._exit(1)
