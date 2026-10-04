;; Original runtime probe: no Foundation agents or simulation mechanisms.
to setup
  clear-all
  reset-ticks
end

to go
  if ticks >= 3 [ stop ]
  tick
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
649
470
16
16
13.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

@#$#@#$#@
## PURPOSE

This empty model tests NetLogo 6.4.x compilation, BehaviorSpace execution and
CSV export. It advances three ticks without creating agents. It is not the
Foundation model and its output is not experimental evidence about Foundation.

## PROVENANCE

Original probe procedures. Document structure and empty Interface view use
NetLogo's built-in blank document template, not a Models Library implementation.
@#$#@#$#@
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
0
@#$#@#$#@
