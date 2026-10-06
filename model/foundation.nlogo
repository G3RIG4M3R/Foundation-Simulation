breed [planets planet]
breed [missionaries missionary]
breed [traders trader]
undirected-link-breed [trade-routes trade-route]

planets-own [
  planet-id kingdom-id capital? foundation?
  population religion tech-dependency trade-trust
  tech-demand tech-health wealth hostility taboo baseline-hostility
  temple? embargoed? policy control-streak controlled?
  successful-trades failed-visits previous-policy-wealth
  last-policy-change-tick policy-cooldown-until
]
missionaries-own [target-planet home-planet mission-skill mode wait-ticks]
traders-own [target-planet origin-planet trade-skill mode cargo wait-ticks]
trade-routes-own [route-strength route-age]

globals [
  foundation-treasury trade-income-this-tick cumulative-trade-profit
  total-executed-missionaries total-executed-traders
  total-rejected-missions total-successful-missions
  total-rejected-trades total-successful-trades
  kingdom-policy-timer tick-limit terminus-planet
  total-recruited-missionaries total-recruited-traders last-recruitment-tick
]

;; INITIALIZATION

to setup
  clear-all
  set tick-limit 450
  set last-recruitment-tick -1
  setup-galaxy
  setup-foundation
  setup-kingdoms
  setup-planets
  initialize-policy-wealth
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
    initialize-missionary
  ]
  create-traders initial-traders [
    initialize-trader
  ]
end

to initialize-missionary
  move-to terminus-planet
  set home-planet terminus-planet
  set target-planet nobody
  set mission-skill 0.75 + random-float 0.50
  set mode "idle"
  set wait-ticks 0
end

to initialize-trader
  move-to terminus-planet
  set origin-planet terminus-planet
  set target-planet nobody
  set trade-skill 0.75 + random-float 0.50
  set mode "idle"
  set cargo 1
  set wait-ticks 0
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
  ;; Local deterministic updates: demand uses incoming health; wear uses incoming
  ;; dependency; substitution uses incoming wealth; the economy uses updated state.
  ;; Sorting avoids spending RNG on independent environmental updates.
  foreach sort planets with [not foundation?] [ world ->
    ask world [ update-planet-economy ]
  ]
end

to update-planet-economy
  set tech-demand clamp01 (tech-demand + 0.006 + 0.01 * (1 - tech-health))
  let maintenance ifelse-value
    (temple? and religion >= 0.60 and policy != "embargo") [0.008] [0]
  ;; Combine wear and its maintenance offset before clipping at either boundary.
  set tech-health clamp01 (tech-health -
    tech-decay-rate * (0.30 + 0.70 * tech-dependency) + maintenance)
  set tech-dependency clamp01 (tech-dependency -
    0.006 * independence-effort * (0.2 + wealth / 100))
  ifelse technology-crisis? [
    set wealth clamp-range (wealth - (0.5 + tech-dependency) * (0.5 - tech-health)) 0 100
  ] [
    set wealth clamp-range (wealth + 0.02 * tech-health) 0 100
  ]
  set trade-trust clamp01 (trade-trust - 0.001)
  ;; Routes decay separately after traders, exactly once per tick.
end

to initialize-policy-wealth
  ;; Policy decisions compare against this bounded snapshot, then replace it;
  ;; environmental updates must not overwrite prior wealth.
  foreach sort planets [ world -> ask world [ set previous-policy-wealth wealth ] ]
  foreach sort planets with [capital?] [ capital ->
    let group [kingdom-id] of capital
    let baseline population-weighted-wealth (planets with [kingdom-id = group])
    ask capital [ set previous-policy-wealth baseline ]
  ]
end

to process-missionaries
  ask planets with [temple? and not foundation?] [ dismantle-repressed-temple ]
  ask missionaries [ step-missionary ]
end

;; MISSIONARIES: one movement and at most one visit per tick.

to step-missionary
  if mode = "detained" [
    set wait-ticks max (list 0 (wait-ticks - 1))
    if wait-ticks = 0 [ set mode "idle" ]
    ;; The release tick is still a full waiting tick; depart next tick.
    stop
  ]
  if mode = "idle" [ select-missionary-destination ]
  if mode = "travel" [ move-missionary ]
end

to select-missionary-destination
  let candidates sort planets with [not foundation? and distance myself > 0]
  set target-planet nobody
  if empty? candidates [ stop ]
  ifelse random-float 1 < 0.15 [
    set target-planet one-of candidates
  ] [
    let weights map [world -> missionary-target-weight world] candidates
    set target-planet weighted-choice candidates weights
  ]
  if target-planet != nobody [ set mode "travel" ]
end

to-report missionary-target-weight [world]
  let temple-factor ifelse-value [temple?] of world [1.5] [1]
  report (0.05 + mission-acceptance-probability world) *
    (0.25 + 1 - [religion] of world) * temple-factor / (1 + distance world / 16)
end

to-report weighted-choice [candidates weights]
  if empty? candidates [ report nobody ]
  if empty? weights [ report one-of candidates ]
  let total sum weights
  if total <= 0 [ report one-of candidates ]
  let draw random-float total
  let cumulative 0
  let index 0
  foreach weights [weight ->
    set cumulative cumulative + weight
    if draw < cumulative [ report item index candidates ]
    set index index + 1
  ]
  ;; Floating-point summation fallback; the final positive weight is eligible.
  report item (last filter [i -> item i weights > 0] (range length weights)) candidates
end

to move-missionary
  if not is-planet? target-planet [
    set target-planet nobody
    set mode "idle"
    stop
  ]
  if [foundation?] of target-planet [
    set target-planet nobody
    set mode "idle"
    stop
  ]
  let remaining distance target-planet
  if remaining > 0 [
    face target-planet
    ifelse remaining <= 1.5 [ move-to target-planet ] [ fd 1.5 ]
  ]
  ;; Center arrival avoids a free snap from the 0.75-unit arrival neighborhood.
  if distance target-planet = 0 [ resolve-missionary-visit ]
end

to resolve-missionary-visit
  if mode != "travel" or not is-planet? target-planet [ stop ]
  if [foundation?] of target-planet or distance target-planet > 0 [ stop ]
  let destination target-planet
  let visitor-skill mission-skill
  ;; Consume the arrival before either outcome, including death.
  set target-planet nobody
  set mode "idle"
  set wait-ticks 0
  ifelse random-float 1 < mission-acceptance-probability destination [
    set total-successful-missions total-successful-missions + 1
    ask destination [ apply-accepted-mission visitor-skill ]
  ] [
    set total-rejected-missions total-rejected-missions + 1
    ask destination [ set failed-visits failed-visits + 1 ]
    if random-float 1 < execution-probability destination [
      set total-executed-missionaries total-executed-missionaries + 1
      die
    ]
    set mode "detained"
    set wait-ticks 2 + random 4
  ]
end

to-report mission-acceptance-probability [world]
  let temple-bonus ifelse-value [temple?] of world [0.10] [0]
  let restriction ifelse-value ([policy] of world = "restrict") [0.18] [0]
  let embargo ifelse-value ([policy] of world = "embargo") [0.35] [0]
  report clamp-range (0.15 + 0.35 * (1 - [hostility] of world) +
    0.15 * [religion] of world + temple-bonus - 0.35 * royal-intolerance -
    0.20 * [taboo] of world - restriction - embargo) 0.02 0.95
end

to-report execution-probability [world]
  let restriction ifelse-value ([policy] of world = "restrict") [0.10] [0]
  let embargo ifelse-value ([policy] of world = "embargo") [0.18] [0]
  report clamp-range (0.01 + 0.12 * [hostility] of world +
    0.10 * royal-intolerance + restriction + embargo) 0 0.55
end

to apply-accepted-mission [visitor-skill]
  set religion clamp01 (religion + missionary-effectiveness * visitor-skill *
    (1 - religion) * (0.40 + 0.60 * tech-dependency))
  if religion >= 0.60 and policy != "embargo" [ set temple? true ]
  dismantle-repressed-temple
  if temple? and policy != "embargo" [ set tech-health clamp01 (tech-health + 0.03) ]
end

to dismantle-repressed-temple
  if religion < 0.35 and member? policy ["restrict" "embargo"] [ set temple? false ]
end

to process-traders
  ask traders [ step-trader ]
end

;; TRADERS: preserve the departure origin until the arrival transaction finishes.

to step-trader
  if mode = "detained" [
    set wait-ticks max (list 0 (wait-ticks - 1))
    if wait-ticks = 0 [ set mode "idle" ]
    stop
  ]
  if mode = "idle" [ select-trader-destination ]
  if mode = "travel" [ move-trader ]
end

to select-trader-destination
  let candidates sort planets with [not foundation? and distance myself > 0]
  set target-planet nobody
  if empty? candidates [ stop ]
  ifelse random-float 1 < 0.15 [
    set target-planet one-of candidates
  ] [
    let weights map [world -> trader-target-weight world] candidates
    set target-planet weighted-choice candidates weights
  ]
  if target-planet != nobody [
    ;; Capacity is renewed between visits; physical inventory is not modeled.
    set cargo 1
    set mode "travel"
  ]
end

to-report trader-target-weight [world]
  let route-factor ifelse-value (direct-trade-route origin-planet world != nobody) [1.75] [1]
  report (0.05 + trade-acceptance-probability world) *
    (0.25 + [tech-demand] of world) * route-factor / (1 + distance world / 16)
end

to-report direct-trade-route [origin destination]
  if not is-planet? origin or not is-planet? destination [ report nobody ]
  if origin = destination [ report nobody ]
  report [trade-route-with destination] of origin
end

to-report trader-travel-speed
  ;; Resolve the link afresh; decay can remove it while the trader is in transit.
  let route direct-trade-route origin-planet target-planet
  if route != nobody [
    if [route-strength] of route >= 0.15 [ report 2.25 ]
  ]
  report 1.5
end

to move-trader
  if not is-planet? target-planet [
    set target-planet nobody
    set mode "idle"
    stop
  ]
  if [foundation?] of target-planet or target-planet = origin-planet [
    set target-planet nobody
    set mode "idle"
    stop
  ]
  let remaining distance target-planet
  if remaining > 0 [
    face target-planet
    let speed trader-travel-speed
    ifelse remaining <= speed [ move-to target-planet ] [ fd speed ]
  ]
  if distance target-planet = 0 [ resolve-trader-visit ]
end

to resolve-trader-visit
  if mode != "travel" or not is-planet? target-planet [ stop ]
  if [foundation?] of target-planet or target-planet = origin-planet [ stop ]
  if distance target-planet > 0 or cargo <= 0 [ stop ]
  let destination target-planet
  let departure origin-planet
  set target-planet nobody
  set mode "idle"
  set wait-ticks 0
  ifelse random-float 1 < trade-acceptance-probability destination [
    let sale-size trade-attractiveness * trade-skill
    ask destination [ apply-trade-sale sale-size ]
    set total-successful-trades total-successful-trades + 1
    let revenue 12 * sale-size
    set trade-income-this-tick trade-income-this-tick + revenue
    set foundation-treasury foundation-treasury + revenue
    set cumulative-trade-profit cumulative-trade-profit + revenue
    ;; Zero-size admissions are counted but cannot create or reinforce routes.
    if sale-size > 0 [ renew-trade-route departure destination sale-size ]
    set cargo 0
  ] [
    set total-rejected-trades total-rejected-trades + 1
    ask destination [ set failed-visits failed-visits + 1 ]
    if random-float 1 < execution-probability destination [
      set total-executed-traders total-executed-traders + 1
      die
    ]
    set mode "detained"
    set wait-ticks 2 + random 4
  ]
  set origin-planet destination
end

to-report trade-acceptance-probability [world]
  let restriction ifelse-value ([policy] of world = "restrict") [0.20] [0]
  let embargo ifelse-value ([policy] of world = "embargo") [0.45] [0]
  report clamp-range (0.10 + religion-trade-weight * [religion] of world +
    0.25 * [tech-demand] of world + 0.15 * [trade-trust] of world -
    0.40 * [hostility] of world - 0.30 * [taboo] of world - restriction - embargo) 0.02 0.95
end

to apply-trade-sale [sale-size]
  set tech-dependency clamp01 (tech-dependency + 0.11 * sale-size)
  set tech-health clamp01 (tech-health + 0.12 * sale-size)
  set trade-trust clamp01 (trade-trust + 0.09 * sale-size)
  set tech-demand clamp01 (tech-demand - 0.15 * sale-size)
  ;; Net development benefit after payment, not a conserved cash balance.
  set wealth clamp-range (wealth + 3 * sale-size) 0 100
  set successful-trades successful-trades + 1
end

to renew-trade-route [origin destination sale-size]
  if sale-size <= 0 [ stop ]
  if not is-planet? origin or not is-planet? destination [ stop ]
  if origin = destination [ stop ]
  let route direct-trade-route origin destination
  ifelse route = nobody [
    ask origin [ create-trade-route-with destination [
      set route-strength 0.35
      set route-age 0
    ] ]
  ] [
    ask route [ set route-strength clamp01 (route-strength + 0.20 * sale-size) ]
  ]
end

to process-trade-routes
  ;; Exactly once after trader activity, including newly established routes.
  ask trade-routes [
    set route-strength clamp01 (route-strength - 0.002)
    set route-age route-age + 1
    if route-strength < 0.08 [ die ]
  ]
end

to process-kingdom-policies
  if ticks mod 10 != 0 or ticks < kingdom-policy-timer [ stop ]
  foreach [1 2 3 4] [ group -> update-kingdom-policy group ]
  foreach sort planets with [kingdom-id = 5] [ world ->
    ask world [ update-independent-policy ]
  ]
  set kingdom-policy-timer ticks + 10
end

to update-kingdom-policy [group]
  let worlds planets with [kingdom-id = group and not foundation?]
  let capitals sort worlds with [capital?]
  if empty? capitals [ stop ]
  let capital first capitals
  ;; All five means use the same population weights. Hostility acts through
  ;; local admission and leverage, not an additional, unspecified threat term.
  let averages kingdom-means worlds
  let dependency item 1 averages
  let current-wealth item 3 averages
  let threat influence-threat averages
  let threshold policy-threat-threshold
  ask capital [
    let next-policy policy
    let crisis? dependency >= 0.60 and current-wealth <= previous-policy-wealth - 2
    ifelse crisis? [
      ;; An already-open government cannot soften further. A continuing crisis
      ;; must not itself trigger a new restriction when the cooldown expires.
      if policy != "open" [
        set next-policy ifelse-value (policy = "embargo") ["restrict"] ["open"]
        set policy-cooldown-until ticks + 20
      ]
    ] [
      ifelse threat < threshold - 0.10 [
        set next-policy "open"
      ] [
        if ticks >= policy-cooldown-until [
          if threat > threshold and policy = "open" [ set next-policy "restrict" ]
          if threat > threshold + 0.15 and dependency < 0.60 [ set next-policy "embargo" ]
        ]
      ]
    ]
    if next-policy != policy [ set last-policy-change-tick ticks ]
    foreach sort worlds [ world -> ask world [ set-government-policy next-policy ] ]
    set previous-policy-wealth current-wealth
  ]
end

to update-independent-policy
  ;; Local hysteresis: embargo releases below .80, restriction below .65.
  ;; High dependency prevents entering embargo, but does not itself lift one.
  let next-policy policy
  if policy = "embargo" and hostility < 0.80 [ set next-policy "restrict" ]
  if hostility < 0.65 [ set next-policy "open" ]
  if hostility > 0.75 and next-policy = "open" [ set next-policy "restrict" ]
  if hostility > 0.90 and tech-dependency < 0.60 [ set next-policy "embargo" ]
  if next-policy != policy [ set last-policy-change-tick ticks ]
  set-government-policy next-policy
end

to set-government-policy [next-policy]
  set policy next-policy
  set embargoed? (policy = "embargo")
end

to recruit-agents
  if ticks mod 10 != 0 or last-recruitment-tick = ticks [ stop ]
  set last-recruitment-tick ticks
  ;; Fixed breed priority under scarce funds; detained travelers still count.
  repeat 2 [
    if count missionaries < initial-missionaries and foundation-treasury >= 10 [
      create-missionaries 1 [ initialize-missionary ]
      set total-recruited-missionaries total-recruited-missionaries + 1
      set foundation-treasury foundation-treasury - 10
      set cumulative-trade-profit cumulative-trade-profit - 10
    ]
  ]
  repeat 2 [
    if count traders < initial-traders and foundation-treasury >= 15 [
      create-traders 1 [ initialize-trader ]
      set total-recruited-traders total-recruited-traders + 1
      set foundation-treasury foundation-treasury - 15
      set cumulative-trade-profit cumulative-trade-profit - 15
    ]
  ]
end

to update-politics-effects
  foreach sort planets with [not foundation?] [ world -> ask world [
    if policy = "restrict" [
      set hostility clamp01 (hostility + 0.002)
      set religion clamp01 (religion - 0.004)
    ]
    if policy = "embargo" [
      set hostility clamp01 (hostility + 0.004)
      set religion clamp01 (religion - 0.009)
    ]
    if policy = "open" [
      ;; Relax only elevated hostility; initial below-baseline jitter is retained.
      if hostility > baseline-hostility [ set hostility max (list baseline-hostility (hostility - 0.001)) ]
      set religion clamp01 (religion + ifelse-value temple? [0.002 * (1 - religion)] [-0.0005])
    ]
    dismantle-repressed-temple
  ] ]
end

to update-control
  foreach sort planets [ world -> ask world [
    ifelse not foundation? and planet-leverage >= 0.58 [
      set control-streak control-streak + 1
    ] [ set control-streak 0 ]
    set controlled? (control-streak >= 5)
  ] ]
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
  foreach sort trade-routes [ route -> ask route [
    set color scale-color blue route-strength -0.25 1.25
    set thickness 0.05 + 0.35 * route-strength
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

to-report planet-leverage
  report clamp01 (0.30 * religion + 0.35 * tech-dependency +
    0.25 * trade-trust + 0.15 * (1 - hostility))
end

to-report controlled-kingdoms
  let result 0
  foreach [1 2 3 4] [ group ->
    let worlds sort planets with [kingdom-id = group]
    let population-sum sum map [world -> [population] of world] worlds
    let controlled-population sum map [world ->
      [ifelse-value controlled? [population] [0]] of world] worlds
    if population-sum > 0 and controlled-population / population-sum >= 0.60 and
      any? planets with [kingdom-id = group and capital? and controlled?] [
      set result result + 1
    ]
  ]
  report result
end

to-report policy-threat-threshold
  report 0.68 - 0.30 * royal-intolerance
end

to-report kingdom-means [worlds]
  let ordered sort worlds
  let weight sum map [world -> [population] of world] ordered
  if weight <= 0 [ report [0 0 0 0 0] ]
  let totals [0 0 0 0 0]
  foreach ordered [ world ->
    let values [(list religion tech-dependency trade-trust wealth hostility)] of world
    let size-weight [population] of world
    set totals (map [[total value] -> total + size-weight * value] totals values)
  ]
  report map [total -> total / weight] totals
end

to-report influence-threat [averages]
  report 0.45 * item 0 averages + 0.40 * item 1 averages + 0.15 * item 2 averages
end

to-report recruitment-costs
  report 10 * total-recruited-missionaries + 15 * total-recruited-traders
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

to-report mean-tech-health
  let worlds sort planets with [not foundation?]
  if empty? worlds [ report 0 ]
  report mean map [world -> [tech-health] of world] worlds
end

to-report mean-tech-demand
  let worlds sort planets with [not foundation?]
  if empty? worlds [ report 0 ]
  report mean map [world -> [tech-demand] of world] worlds
end

to-report mean-wealth
  let worlds sort planets with [not foundation?]
  if empty? worlds [ report 0 ]
  report mean map [world -> [wealth] of world] worlds
end

to-report technology-crisis?
  report tech-dependency > 0.45 and tech-health < 0.50
end

to-report technology-crisis-planets
  report count planets with [not foundation? and technology-crisis?]
end

to-report population-weighted-wealth [worlds]
  let ordered sort worlds
  let weight sum map [world -> [population] of world] ordered
  if weight <= 0 [ report 0 ]
  report (sum map [world -> [population * wealth] of world] ordered) / weight
end

to-report active-trade-links
  ;; Counts all extant relationships, including weak remnants below speed threshold.
  report count trade-routes
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
  if count trade-routes > count planets * (count planets - 1) / 2 [ report false ]
  if tick-limit != 450 or not in-range? ticks 0 tick-limit [ report false ]
  if not natural-number? ticks [ report false ]
  if not in-range? last-recruitment-tick -1 ticks [ report false ]
  if last-recruitment-tick != floor last-recruitment-tick [ report false ]
  if not in-range? foundation-treasury 0 1.0E+300 [ report false ]
  if not in-range? cumulative-trade-profit (-1.0E+300) 1.0E+300 [ report false ]
  if not in-range? trade-income-this-tick 0 1.0E+300 [ report false ]
  report empty? filter [value -> not natural-number? value] (list
    total-executed-missionaries total-executed-traders total-rejected-missions
    total-successful-missions total-rejected-trades total-successful-trades kingdom-policy-timer
    total-recruited-missionaries total-recruited-traders)
end

to-report planet-state-valid?
  if xcor != pxcor or ycor != pycor [ report false ]
  if not natural-number? kingdom-id or kingdom-id > 5 [ report false ]
  if not in-range? population 0.5 1.5 [ report false ]
  if not in-range? wealth 0 100 [ report false ]
  if not in-range? previous-policy-wealth 0 100 [ report false ]
  if not natural-number? last-policy-change-tick or not natural-number? policy-cooldown-until [ report false ]
  if not empty? filter [value -> not in-range? value 0 1] (list
    religion tech-dependency trade-trust tech-demand tech-health hostility taboo baseline-hostility
  ) [ report false ]
  if not empty? filter [value -> not is-boolean? value] (list
    capital? foundation? temple? embargoed? controlled?
  ) [ report false ]
  if not member? policy ["open" "restrict" "embargo"] [ report false ]
  if embargoed? != (policy = "embargo") [ report false ]
  if foundation? and (controlled? or capital? or policy != "open") [ report false ]
  if controlled? != (control-streak >= 5) [ report false ]
  report empty? filter [value -> not natural-number? value]
    (list control-streak successful-trades failed-visits)
end

to-report destination-valid?
  if not member? mode ["idle" "travel" "detained"] [ report false ]
  if not natural-number? wait-ticks [ report false ]
  if mode = "travel" and target-planet = nobody [ report false ]
  if mode != "travel" and target-planet != nobody [ report false ]
  if mode = "detained" and not in-range? wait-ticks 1 5 [ report false ]
  if mode != "detained" and wait-ticks != 0 [ report false ]
  if target-planet = nobody [ report mode = "idle" or mode = "detained" ]
  if not is-planet? target-planet [ report false ]
  report not [foundation?] of target-planet
end

to-report missionary-state-valid?
  report destination-valid? and is-planet? home-planet and in-range? mission-skill 0.75 1.25
end

to-report trader-state-valid?
  if mode = "travel" and target-planet = origin-planet [ report false ]
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

A Foundation-inspired study of non-military influence through missions and trade.
The world contains Terminus, four kingdoms of five planets each, and ten
independent markets. The period and star map are fictional abstractions.

## HOW TO USE IT

Click setup to create a new galaxy. go-once advances one tick; go runs to 450.
All planets remain stationary. Missionaries depart from Terminus, travel between
worlds, and attempt to spread Scientism. Traders negotiate sales and establish
trading relationships. Infrastructure wears, demand regenerates, and domestic
substitution reduces dependency. Governments respond to influence and economic
crises; the Foundation can pay to replace lost travelers.

The two initial-count sliders set starting populations. missionary-effectiveness
scales conversion; royal-intolerance lowers missionary admission and raises
execution risk for both visitor types. trade-attractiveness scales sales, and
religion-trade-weight sets religion's contribution to trader admission.
tech-decay-rate sets infrastructure wear; independence-effort scales gradual
domestic substitution. view-mode changes
planet color only: kingdom, religion, dependency or control. Terminus is always
a gold star; capitals are ringed and labeled. Cyan arrows represent missionaries
and white squares represent traders; agents at the same location overlap.

## MISSIONARY RULES

Each missionary selects a world other than Terminus or its current planet:
15% uniform exploration, otherwise a weighted random choice favoring admission,
remaining conversion potential, temples and proximity. Admission is drawn only
on arrival. Travel follows the shortest toroidal path at up to 1.5 units per
tick, reaching the planet center before exactly one visit is resolved.

Acceptance depends on local hostility, religion, temples, taboo, policy and
royal-intolerance. Probabilities are bounded [.02,.95]. Accepted conversion is
missionary-effectiveness * mission-skill * (1 - religion) *
(.40 + .60 * tech-dependency). Skill is sampled in [.75,1.25).
Religion stays in [0,1]. At religion >= .60, a temple can form unless embargoed;
an active temple repairs health by .03 per accepted visit, up to 1.
Embargo blocks construction and repair, even on rare accepted missions.
Under restrict/embargo, a temple is dismantled when religion < .35.

A rejected missionary is executed with a separate state-dependent probability
bounded [0,.55], or detained at the destination for 2–5 complete subsequent
ticks. Survivors then choose another world. Paid recruitment can replace deaths.
total-successful-missions, total-rejected-missions and
total-executed-missionaries are cumulative since setup. Planet failed-visits
counts rejections. Missionary activity produces no trade income or routes.

## TRADERS AND ROUTES

Traders also explore uniformly with probability .15; otherwise they choose
destinations with weight (.05 + admission probability) * (.25 + demand) *
(1 + .75 * existing-direct-route-indicator) / (1 + distance / 16).
Terminus and the trader's current planet are excluded. Traders arrive at planet
centers using toroidal shortest paths. Speed is 1.5 units/tick, or 2.25 if the
direct origin-destination route exists with strength >= .15. A route may fade
during travel; the speed is checked again each tick. Weak remnants retain the
targeting preference but provide no speed bonus. Unconnected worlds remain reachable.

Admission probability is clamped to [.02,.95]:
.10 + religion-trade-weight * religion + .25 * tech-demand + .15 * trade-trust
- .40 * hostility - .30 * taboo - .20 if restricted - .45 if embargoed.
Religion improves admission but is never a prerequisite. Rejection causes
detention or execution using the same rule as missionary rejection. Each
arrival resolves once. Surviving traders depart from the visited world.

For an accepted visit, sale-size = trade-attractiveness * trade-skill. A sale
adds .11 * sale-size to dependency, .12 * sale-size to health, .09 * sale-size
to trust, subtracts .15 * sale-size from demand, and adds 3 * sale-size to
wealth. Normalized values are clamped to [0,1], wealth to [0,100]. Trading
does not convert religion or construct temples. Cargo is an abstract per-visit
capacity of 1, consumed on acceptance and restored on departure, not an
inventory or an upper bound on sale-size. Skill is sampled in [.75,1.25).

Revenue of 12 * sale-size credits is booked once to treasury, current-tick
income and cumulative profit. Planet wealth is a net development benefit after
payment, not a conserved cash account. Initial travelers are free, with no
upkeep. Cumulative profit is revenue minus recruitment spending and may be negative.
total-successful-trades and planet successful-trades count accepted visits,
including zero-size admissions. At trade-attractiveness = 0, acceptance changes
these counters only: no revenue, market-state change or route reinforcement.
Planet failed-visits counts rejected missions and trades together.

A positive sale creates an undirected route between departure and destination
at strength .35 and age 0; later sales on either direction add .20 * sale-size,
clamped to 1. Age counts ticks since creation and is not reset by reinforcement.
After all traders act, each route loses .002 strength and ages once, including
new routes. Routes below .08 are deleted. Strong links are brighter and thicker;
styling changes neither state nor randomness. active-trade-links counts all
remaining relationships, including weak remnants.

## TECHNOLOGY AND ECONOMY

At the beginning of each tick, each external planet updates locally in this order:
1. Demand rises by .006 + .01 * (1 - incoming health).
2. Health loses tech-decay-rate * (.30 + .70 * incoming dependency). A temple
   offsets .008 only at religion >= .60 and policy other than embargo. Wear
   and maintenance are combined before clamping. Accepted missionary repairs
   and trader replenishment occur later in the tick.
3. Dependency falls by .006 * independence-effort * (.2 + incoming wealth / 100).
   Zero effort disables substitution. It does not cost extra wealth in this
   abstraction; no industrial production chain or investment budget is modeled.
4. If updated dependency > .45 and health < .50, wealth loses
   (.5 + dependency) * (.5 - health); otherwise it recovers .02 * health.
5. Trade trust falls by .001. Route wear runs separately after trading.

Normalized states remain in [0,1] and wealth in [0,100]. Terminus is exempt.
Embargo has no instantaneous wealth penalty: missing maintenance and fewer
sales cause deterioration, which can trigger a delayed economic crisis.
Reopening alone cannot instantly repair infrastructure. Substitution can end
the dependency crisis even with poor health; wealth recovery then remains slow.
Religion does not directly create or remove dependency. Secular planets can
become dependent through successful sales; religious influence and trade trust
remain separate attributes.

mean-tech-health, mean-tech-demand and mean-wealth are unweighted external-world
means; technology-crisis-planets counts external worlds meeting both crisis
conditions. mean-religion and mean-dependency likewise exclude Terminus. These
pure reporters support Command Center and BehaviorSpace observations.
previous-policy-wealth holds the previous decision's population-weighted kingdom
wealth on capitals (initialized during setup). Decisions compare before refreshing
this snapshot; no growing history is retained. Other planets retain initial local
wealth, with no independent-world crisis concession in this version.

## GOVERNMENT, REPRESSION AND CONTROL

The full tick order is environment, missionaries, traders, route wear, periodic
policies/recruitment, local political effects, control, appearance, then tick.
Policy and recruitment intervals begin at tick 0 and repeat every 10 ticks.
All five planets in each kingdom share their capital's policy. Decisions use
population-weighted means R (religion), D (dependency), T (trust), W (wealth),
and H (hostility). Threat = .45 R + .40 D + .15 T; H acts through local admission
and leverage, without a separate threat coefficient or kingdom-name rule.

The restriction threshold is .68 - .30 * royal-intolerance. Threat strictly above
it triggers restrict; threat above threshold + .15 triggers embargo only if
D < .60. A restrictive policy persists until threat < threshold - .10, or an
economic concession. Existing embargoes are not automatically lifted merely
because D reaches .60. If D >= .60 and W has fallen at least 2 wealth units since
the previous decision, embargo softens to restrict, or restrict to open. Each
concession blocks escalation for 20 ticks; further concessions/release may occur
during cooldown. An already-open government stays open while the measured crisis
continues; this does not extend cooldown. No wealth is awarded. Capitals store the last transition tick
and cooldown expiry. kingdom-policy-timer records the next scheduled decision.

Independent worlds decide locally: hostility > .75 triggers restrict; hostility
> .90 and dependency < .60 triggers embargo. Embargo releases below .80, and
restriction below .65. Dependency gates entry, not release. These worlds share
no government. Terminus remains open and exempt from political effects.

Each tick restrict raises hostility .002 and lowers religion .004; embargo raises
hostility .004 and lowers religion .009. Open policies reduce elevated hostility
.001 toward baseline, without raising below-baseline initial jitter. An open
temple sustains religion by .002 * (1 - religion); without a temple religion
loses .0005. Values clamp to [0,1]. Repression dismantles temples below .35.
There is no neighboring religious contagion or predetermined historical event.

Planet leverage = clamp01(.30 * religion + .35 * dependency + .25 * trade-trust
+ .15 * (1 - hostility)). This is an influence index, not a probability. Leverage
>= .58 for five consecutive ticks establishes effective control. One lower tick
resets the streak and control immediately. Conversion alone cannot establish
control; secular economic ties can. controlled-planets excludes Terminus and
control-fraction divides by 30. controlled-kingdoms requires both a controlled
capital and at least .60 of kingdom population living on controlled worlds.
Control is reversible influence, not annexation; kingdom identities never change.

Recruitment fills toward the two initial-count sliders every 10 ticks, at most
two missionaries and two traders per interval. Living detained travelers count.
Missionaries cost 10 credits each and are funded first; traders cost 15. Partial
recruitment is allowed, but spending never overdraws treasury. New travelers
start idle at Terminus and act on the following tick. Initial agents remain free.
Cumulative total-recruited-missionaries, total-recruited-traders and recruitment-costs
support exact population and financial audits. Treasury equals 200 plus cumulative
trade profit under ordinary simulation; current-tick trade income is gross sales.

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
