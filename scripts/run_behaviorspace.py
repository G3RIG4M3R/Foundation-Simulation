#!/usr/bin/env python3
"""Run the unmodified model, preserving raw output and scientific provenance."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import time

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def run(home, xml, name, csv, threads=1):
    root=Path(__file__).resolve().parents[1]
    model=root/'model/foundation.nlogo'
    csv=Path(csv).resolve(); xml=Path(xml).resolve()
    if threads < 1: raise ValueError('Threads must be positive')
    csv.parent.mkdir(parents=True,exist_ok=True)
    provenance=csv.with_suffix('.provenance.json')
    if csv.exists() or provenance.exists(): raise ValueError(f'Refusing to overwrite evidence: {csv}')
    cmd=[str(Path(home).resolve()/'NetLogo_Console'),'--headless','--model',str(model),
         '--setup-file',str(xml),'--experiment',name,'--table',str(csv),'--threads',str(threads)]
    info={'command':cmd,'started_utc':datetime.now(timezone.utc).isoformat(),
          'model_sha256':digest(model),'experiment_sha256':digest(xml),'seed_scheme':'100000 + behaviorspace-run-number (unless explicit representative replay seed)',
          'status':'running'}
    provenance.write_text(json.dumps(info,indent=2)+'\n')
    start=time.monotonic()
    result=subprocess.run(cmd,capture_output=True,text=True)
    info.update(elapsed_seconds=time.monotonic()-start,returncode=result.returncode,
                finished_utc=datetime.now(timezone.utc).isoformat(),status='runtime completed; data audit required')
    if csv.exists(): info['csv_sha256']=digest(csv)
    if result.returncode or 'RUNTIME ERROR' in result.stdout+result.stderr:
        info['status']='failed; raw partial data preserved'
    provenance.write_text(json.dumps(info,indent=2)+'\n')
    print(result.stdout+result.stderr,end='')
    print(f'{info["status"]}: {csv} ({info["elapsed_seconds"]:.2f}s)',flush=True)
    if info['status'].startswith('failed'): raise ValueError('NetLogo execution failed')
    return info

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('netlogo_home');p.add_argument('xml');p.add_argument('experiment');p.add_argument('csv')
    p.add_argument('threads',type=int,nargs='?',default=1)
    a=p.parse_args()
    try: run(a.netlogo_home,a.xml,a.experiment,a.csv,a.threads)
    except (ValueError,OSError) as e: raise SystemExit(f'FAIL: {e}')
