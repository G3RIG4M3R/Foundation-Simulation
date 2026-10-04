# NetLogo environment

Verified on 2026-10-04:

| Component | Observed value |
| --- | --- |
| OS | Ubuntu 24.04.4 LTS, x86_64, WSL2 |
| Kernel | 6.6.87.2-microsoft-standard-WSL2 |
| NetLogo | 6.4.0 (JAR version metadata: November 14, 2023) |
| Installation | `/home/adam/tools/NetLogo-6.4.0-64` |
| Native launcher | `NetLogo_Console`, symlink to `bin/NetLogo` |
| Bundled runtime | Java 17.0.8.1, from `lib/runtime/release` |
| Check dependency | Python 3 standard library only |

The native console successfully compiled the original empty `.nlogo` runtime
fixture and executed its external BehaviorSpace XML: two runs, eight data rows,
steps/ticks 0–3 in each run, and zero agents. The actual `netlogo-version`
reporter returned `6.4.0`. This verifies the runtime and CSV path only.

From the repository root:

```bash
python3 scripts/check_netlogo.py /home/adam/tools/NetLogo-6.4.0-64
```

The runner accepts another installation path and invokes the native console
with `--headless`, the fixture model/XML, `--threads 1`, and `--table` in a
temporary directory. It validates experiment metadata, version, columns,
row counts, run IDs, steps, ticks, world dimensions, and absence of agents.
The temporary output is removed afterward; it is not research data.

The fixture's 33×33 view is the built-in blank document view. The Foundation
world will be 64×64 when implemented. Only the blank document serialization
was used; no Models Library procedures were copied.

For direct CLI discovery:

```bash
/home/adam/tools/NetLogo-6.4.0-64/NetLogo_Console --headless --help
```

No standalone `java` executable is on PATH, and the bundled runtime has no
`bin/java`. The supplied `netlogo-headless.sh` expects a shell Java executable;
use the working native console in this environment. The installed
`docs/behaviorspace.html` is the appropriate 6.4.0 reference.

GUI operation has not been verified. The Foundation model, its 450-tick run,
world topology, interface, and scientific behavior have not been tested.
