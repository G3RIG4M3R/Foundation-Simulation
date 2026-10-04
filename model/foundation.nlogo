breed [planets planet]
breed [missionaries missionary]
breed [traders trader]
undirected-link-breed [trade-routes trade-route]

planets-own [
  planet-id kingdom-id capital? foundation?
  population religion tech-dependency trade-trust
  tech-demand tech-health wealth hostility taboo baseline-hostility
  temple? embargoed? policy control-streak controlled?
  successful-trades failed-visits
]
missionaries-own [target-planet home-planet mission-skill mode wait-ticks]
traders-own [target-planet origin-planet trade-skill mode cargo wait-ticks]
trade-routes-own [route-strength route-age]

globals [
  foundation-treasury trade-income-this-tick cumulative-trade-profit
  total-executed-missionaries total-executed-traders
  total-rejected-missions total-rejected-trades total-successful-trades
  kingdom-policy-timer tick-limit terminus-planet
]

;; INITIALIZATION

to setup
  clear-all
  set tick-limit 450
  setup-galaxy
  setup-foundation
  setup-kingdoms
  setup-planets
  setup-agents
  reset-ticks
  update-appearance
end

to setup-galaxy
  resize-world -32 31 -32 31
  ;; Both wrap axes are stored in the Interface view settings.
  ask patches [ set pcolor black ]
end

to setup-foundation
  set foundation-treasury 200
  ;; clear-all resets all cumulative counters and per-tick income to zero.
  create-world 0 0 false (patch 0 0)
  set terminus-planet one-of planets with [foundation?]
  ask terminus-planet [
    set population 1
    set religion 1
    set trade-trust 1
    set tech-health 1
    set wealth 100
    set temple? true
    set label "Terminus"
  ]
end

to setup-kingdoms
  let names ["Anacreon" "Smyrno" "Konom" "Daribow"]
  ;; Explicit group/slot IDs do not depend on creation order or turtle who.
  foreach [1 2 3 4] [ group ->
    let center item (group - 1) kingdom-centers
    let sites patches with [distance center <= 6]
    foreach [0 1 2 3 4] [ slot ->
      let site center
      if slot > 0 [ set site choose-planet-site sites ]
      create-world (1 + (group - 1) * 5 + slot) group (slot = 0) site
    ]
    ask planets with [kingdom-id = group and capital?] [
      set label item (group - 1) names
    ]
  ]
end

to setup-planets
  ;; Independent markets are outside all four cluster disks, with a buffer.
  let centers kingdom-centers
  let sites patches with [
    all? (patch-set centers) [distance myself > 8]
  ]
  foreach (range 21 31) [ id ->
    create-world id 5 false (choose-planet-site sites)
  ]
  foreach sort planets with [not foundation?] [ world ->
    ask world [ initialize-external-state ]
  ]
end

to-report kingdom-centers
  report (list (patch -18 18) (patch 18 18)
               (patch -18 -18) (patch 18 -18))
end

to-report choose-planet-site [candidates]
  if not any? candidates [ error "Planet placement: no eligible patches." ]
  ;; Rejection sampling keeps placement stochastic but failure bounded.
  repeat 1000 [
    let site one-of candidates
    if not any? planets with [distance site < 3] [ report site ]
  ]
  error "Planet placement: no separated site found after 1000 attempts."
end

to create-world [id group is-capital site]
  create-planets 1 [
    set planet-id id
    set kingdom-id group
    set capital? is-capital
    set foundation? (group = 0)
    set temple? false
    set embargoed? false
    set controlled? false
    set policy "open"
    set control-streak 0
    set successful-trades 0
    set failed-visits 0
    set heading 0
    move-to site
  ]
end

to initialize-external-state
  set population 0.5 + random-float 1
  set religion 0.02 + random-float 0.18
  set tech-dependency random-float 0.08
  set trade-trust random-float 0.10
  set tech-health 0.65 + random-float 0.25
  set tech-demand 0.40 + random-float 0.40
  set wealth 40 + random-float 40
  set taboo random-float 0.35
  ifelse kingdom-id = 5 [
    set baseline-hostility 0.15 + random-float 0.65
    set hostility baseline-hostility
  ] [
    set baseline-hostility item (kingdom-id - 1) [0.60 0.25 0.50 0.40]
    set hostility clamp01 (baseline-hostility - 0.10 + random-float 0.20)
  ]
end

to setup-agents
  create-missionaries initial-missionaries [
    move-to terminus-planet
    set home-planet terminus-planet
    set target-planet nobody
    set mission-skill 0.75 + random-float 0.50
    set mode "idle"
    set wait-ticks 0
  ]
  create-traders initial-traders [
    move-to terminus-planet
    set origin-planet terminus-planet
    set target-planet nobody
    set trade-skill 0.75 + random-float 0.50
    set mode "idle"
    set cargo 1
    set wait-ticks 0
  ]
end

;; SCHEDULER: go is the only procedure that advances simulation time.

to go
  if ticks >= tick-limit [ stop ]
  set trade-income-this-tick 0
  process-environment
  process-missionaries
  process-traders
  process-trade-routes
  if ticks mod 10 = 0 [
    process-kingdom-policies
    recruit-agents
  ]
  update-politics-effects
  update-control
  update-appearance
  tick
end

to go-once
  go
end

to process-environment
  ;; TODO Stage 4: demand, infrastructure, substitution and wealth.
end

to process-missionaries
  ;; TODO Stage 2: travel and mission visits. Agents remain idle for now.
end

to process-traders
  ;; TODO Stage 3: travel and transactions. Agents remain idle for now.
end

to process-trade-routes
  ;; TODO Stage 3: decay routes exactly once, after trader activity.
end

to process-kingdom-policies
  ;; TODO Stage 5: capital-led policies and independent-world decisions.
end

to recruit-agents
  ;; TODO Stage 5: replacements charged to the Foundation treasury.
end

to update-politics-effects
  ;; TODO Stage 5: local repression and institutional persistence.
end

to update-control
  ;; TODO Stage 5: consecutive-tick influence threshold.
end

;; DISPLAY: sorted single-agent asks avoid consuming the simulation RNG.

to update-appearance
  foreach sort planets [ world -> ask world [ style-planet ] ]
  foreach sort missionaries [ visitor -> ask visitor [
    set shape "missionary"
    set color cyan
    set size 1.2
  ] ]
  foreach sort traders [ visitor -> ask visitor [
    set shape "trader"
    set color white
    set size 1.2
  ] ]
end

to style-planet
  set shape ifelse-value capital? ["capital"] ["planet"]
  set size ifelse-value capital? [2.2] [1.6]
  set label-color white
  if view-mode = "kingdom" [
    set color item kingdom-id [45 15 105 65 125 5]
  ]
  ;; Retain a visible tint at zero instead of hiding low values in black space.
  if view-mode = "religion" [ set color scale-color green religion -0.4 1 ]
  if view-mode = "dependency" [ set color scale-color sky tech-dependency -0.4 1 ]
  if view-mode = "control" [ set color ifelse-value controlled? [green] [gray] ]
  if foundation? [
    set shape "foundation"
    set color yellow
    set size 3
  ]
end

;; PURE STATE REPORTERS

to-report clamp-range [value lower upper]
  report max (list lower (min (list upper value)))
end

to-report clamp01 [value]
  report clamp-range value 0 1
end

to-report controlled-planets
  report count planets with [not foundation? and controlled?]
end

to-report control-fraction
  report controlled-planets / 30
end

to-report mean-religion
  let worlds sort planets with [not foundation?]
  if empty? worlds [ report 0 ]
  report mean map [world -> [religion] of world] worlds
end

to-report mean-dependency
  let worlds sort planets with [not foundation?]
  if empty? worlds [ report 0 ]
  report mean map [world -> [tech-dependency] of world] worlds
end

to-report in-range? [value lower upper]
  if not is-number? value [ report false ]
  report value >= lower and value <= upper
end

to-report natural-number? [value]
  if not is-number? value [ report false ]
  report value >= 0 and value = floor value
end

to-report model-valid?
  if (list min-pxcor max-pxcor min-pycor max-pycor) != [-32 31 -32 31] [ report false ]
  ;; Toroidal distance of one patch across each seam checks both wrapping axes.
  if [distance patch 31 0] of patch -32 0 != 1 [ report false ]
  if [distance patch 0 31] of patch 0 -32 != 1 [ report false ]
  if count planets != 31 or count planets with [foundation?] != 1 [ report false ]
  if not is-planet? terminus-planet [ report false ]
  if not [foundation?] of terminus-planet [ report false ]
  if [planet-id] of terminus-planet != 0 [ report false ]
  if [kingdom-id] of terminus-planet != 0 [ report false ]
  if count planets with [kingdom-id = 5] != 10 [ report false ]
  if any? planets with [capital? and not member? kingdom-id [1 2 3 4]] [ report false ]
  let worlds sort planets
  if sort map [world -> [planet-id] of world] worlds != range 31 [ report false ]
  if not empty? filter [group ->
    count planets with [kingdom-id = group] != 5 or
    count planets with [kingdom-id = group and capital?] != 1
  ] [1 2 3 4] [ report false ]
  if not empty? filter [world -> not [planet-state-valid?] of world] worlds [ report false ]
  if not empty? filter [world ->
    any? planets with [self != world and distance world < 3]
  ] worlds [ report false ]
  if not empty? filter [visitor -> not [missionary-state-valid?] of visitor] sort missionaries [ report false ]
  if not empty? filter [visitor -> not [trader-state-valid?] of visitor] sort traders [ report false ]
  if any? trade-routes with [
    not is-planet? end1 or not is-planet? end2 or end1 = end2 or
    not in-range? route-strength 0 1 or not natural-number? route-age
  ] [ report false ]
  if tick-limit != 450 or not in-range? ticks 0 tick-limit [ report false ]
  if not natural-number? ticks [ report false ]
  if not in-range? foundation-treasury 0 1.0E+300 [ report false ]
  if not in-range? cumulative-trade-profit (-1.0E+300) 1.0E+300 [ report false ]
  if not in-range? trade-income-this-tick 0 1.0E+300 [ report false ]
  report empty? filter [value -> not natural-number? value] (list
    total-executed-missionaries total-executed-traders total-rejected-missions
    total-rejected-trades total-successful-trades kingdom-policy-timer)
end

to-report planet-state-valid?
  if xcor != pxcor or ycor != pycor [ report false ]
  if not natural-number? kingdom-id or kingdom-id > 5 [ report false ]
  if not in-range? population 0.5 1.5 [ report false ]
  if not in-range? wealth 0 100 [ report false ]
  if not empty? filter [value -> not in-range? value 0 1] (list
    religion tech-dependency trade-trust tech-demand tech-health hostility taboo baseline-hostility
  ) [ report false ]
  if not empty? filter [value -> not is-boolean? value] (list
    capital? foundation? temple? embargoed? controlled?
  ) [ report false ]
  if not member? policy ["open" "restrict" "embargo"] [ report false ]
  if embargoed? != (policy = "embargo") [ report false ]
  if foundation? and (controlled? or capital? or embargoed?) [ report false ]
  if controlled? != (control-streak >= 5) [ report false ]
  report empty? filter [value -> not natural-number? value]
    (list control-streak successful-trades failed-visits)
end

to-report destination-valid?
  if not member? mode ["idle" "travel" "detained"] [ report false ]
  if not natural-number? wait-ticks [ report false ]
  if target-planet = nobody [ report mode = "idle" or mode = "detained" ]
  if not is-planet? target-planet [ report false ]
  report not [foundation?] of target-planet
end

to-report missionary-state-valid?
  report destination-valid? and is-planet? home-planet and in-range? mission-skill 0.75 1.25
end

to-report trader-state-valid?
  report destination-valid? and is-planet? origin-planet and
    in-range? trade-skill 0.75 1.25 and in-range? cargo 0 1
end

to assert-valid-model-state
  if not model-valid? [ error "Invalid galaxy, agent state, counters or clock." ]
end
@#$#@#$#@
GRAPHICS-WINDOW
320
10
840
531
-1
-1
8.0
1
10
1
1
1
0
1
1
1
-32
31
-32
31
1
1
1
ticks
30.0

BUTTON
10
10
100
43
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
108
10
198
43
go-once
go-once
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
206
10
296
43
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
10
60
300
93
initial-missionaries
initial-missionaries
0
40
12.0
2
1
NIL
HORIZONTAL

SLIDER
10
105
300
138
missionary-effectiveness
missionary-effectiveness
0
0.5
0.25
0.05
1
NIL
HORIZONTAL

SLIDER
10
150
300
183
initial-traders
initial-traders
0
40
12.0
2
1
NIL
HORIZONTAL

SLIDER
10
195
300
228
trade-attractiveness
trade-attractiveness
0
1
0.6
0.05
1
NIL
HORIZONTAL

SLIDER
10
240
300
273
royal-intolerance
royal-intolerance
0
1
0.5
0.05
1
NIL
HORIZONTAL

SLIDER
10
285
300
318
tech-decay-rate
tech-decay-rate
0
0.04
0.015
0.005
1
NIL
HORIZONTAL

SLIDER
10
330
300
363
religion-trade-weight
religion-trade-weight
0
0.8
0.55
0.05
1
NIL
HORIZONTAL

SLIDER
10
375
300
408
independence-effort
independence-effort
0
1
0.15
0.05
1
NIL
HORIZONTAL

CHOOSER
10
425
300
470
view-mode
view-mode
"kingdom" "religion" "dependency" "control"
0

@#$#@#$#@
## WHAT IS IT?

A galaxy initialization for a Foundation-inspired study of non-military influence.
The world contains Terminus, four kingdoms of five planets each, and ten
independent markets. The period and star map are fictional abstractions.

## HOW TO USE IT

Click setup to create a new galaxy. go-once advances one tick; go runs to 450.
All planets remain stationary. Missionaries and traders are initialized at
Terminus and stay idle in this version. No religious, trading, economic or
political processes operate yet. No experimental results are claimed.

The two initial-count sliders set the number of idle travelers. The other six
sliders reserve the parameters for subsequent model behavior. view-mode changes
planet color only: kingdom, religion, dependency or control. Terminus is always
a gold star; capitals are ringed and labeled. Cyan arrows represent missionaries
and white squares represent traders; idle travelers overlap at Terminus.

## INITIALIZATION

The 64 by 64 grid wraps horizontally and vertically. Kingdom capitals lie at
(+/-18, +/-18); other kingdom planets are within six patches of their capital.
Independent planets lie beyond eight patches from every capital. All planets
are at least three toroidal distance units apart. IDs are explicit attributes,
independent of turtle creation order. Placement stops with an error after
1000 unsuccessful attempts for a planet.

External state is sampled uniformly within the specified ranges: religion
[.02,.20), dependency [0,.08), trust [0,.10), health [.65,.90), demand [.40,.80),
wealth [40,80), taboo [0,.35), and population [.5,1.5). Kingdom hostility is
its baseline plus jitter [-.10,.10); independent hostility is [.15,.80).
The Foundation treasury starts at 200 credits; initial travelers are free.

For repeatable initialization, enter random-seed 42 setup in the Command Center.
setup does not reset the seed itself. Colors do not consume random numbers.

## CREDITS

Original model, inspired by Isaac Asimov's Foundation. Developed for Collective
Intelligence, Autumn 2026, assignment by Tamás Takács. Source license: MIT,
Copyright (c) 2026 G3RIG4M3R. No Models Library simulation code is used.
@#$#@#$#@
default
true
0
Circle -7500403 true true 75 75 150

capital
false
0
Circle -7500403 false true 0 0 300
Circle -7500403 true true 65 65 170

foundation
false
0
Polygon -7500403 true true 150 0 184 101 290 104 205 168 236 270 150 210 64 270 95 168 10 104 116 101

missionary
true
0
Polygon -7500403 true true 150 0 285 285 150 200 15 285

planet
false
0
Circle -7500403 true true 15 15 270

trader
true
0
Rectangle -7500403 false true 35 35 265 265
Line -7500403 true 35 35 265 265
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
setup
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
