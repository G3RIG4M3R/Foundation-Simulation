;; ========================================
;; 1. GLOBAL VARIABLES AND AGENT DEFINITIONS
;; ========================================

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
  kingdom-policy-timer active-tick-limit terminus-planet
  total-recruited-missionaries total-recruited-traders last-recruitment-tick
]

;; ========================================
;; 2. WORLD INITIALIZATION
;; ========================================

;; INITIALIZATION

to setup
  ;; Capture the widget/BehaviorSpace value before clear-all. Mid-run changes to
  ;; tick-limit therefore apply only after the next setup.
  let requested-tick-limit tick-limit
  clear-all
  set tick-limit requested-tick-limit
  set active-tick-limit requested-tick-limit
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

;; ========================================
;; 3. PLANET MECHANICS
;; ========================================

;; SCHEDULER: go is the only procedure that advances simulation time.

to go
  ;; Zero is the interactive "unlimited" setting. BehaviorSpace experiments
  ;; always set a positive horizon and also carry a matching time limit.
  if active-tick-limit > 0 and ticks >= active-tick-limit [ stop ]
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

;; ========================================
;; 4. MISSIONARY BEHAVIOR
;; ========================================

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

;; ========================================
;; 5. TRADER BEHAVIOR
;; ========================================

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

;; ========================================
;; 6. TECHNOLOGICAL DEPENDENCY
;; ========================================

to process-trade-routes
  ;; Exactly once after trader activity, including newly established routes.
  ask trade-routes [
    set route-strength clamp01 (route-strength - 0.002)
    set route-age route-age + 1
    if route-strength < 0.08 [ die ]
  ]
end

;; ========================================
;; 7. KINGDOM POLITICS AND RESISTANCE
;; ========================================

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

;; ========================================
;; 8. STATISTICS AND METRICS
;; ========================================

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
  let policy-mark ifelse-value (policy = "open") [""] [
    ifelse-value (policy = "restrict") ["R"] ["E"] ]
  set label policy-mark
  if capital? [
    set label item (kingdom-id - 1) ["Anacreon" "Smyrno" "Konom" "Daribow"]
    if policy-mark != "" [ set label (word label " [" policy-mark "]") ]
  ]
  if view-mode = "kingdom" [
    set color item kingdom-id [45 15 105 65 125 5]
  ]
  ;; Red -> amber -> green with a monotonic hue; no RNG or state feedback.
  if view-mode = "religion" [ set color religion-color religion ]
  if view-mode = "dependency" [ set color scale-color sky tech-dependency -0.4 1 ]
  if view-mode = "control" [ set color ifelse-value controlled? [green] [gray] ]
  if foundation? [
    set label "Terminus"
    set shape "foundation"
    set color yellow
    set size 3
  ]
end

to-report religion-color [level]
  let fraction clamp01 level
  if fraction <= 0.5 [ report (list 220 (70 + 280 * fraction) 60) ]
  report (list (220 - 320 * (fraction - 0.5)) 210 60)
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
  if not valid-tick-limit? tick-limit [ report false ]
  if not valid-tick-limit? active-tick-limit [ report false ]
  if ticks < 0 [ report false ]
  if active-tick-limit > 0 and ticks > active-tick-limit [ report false ]
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

to-report valid-tick-limit? [value]
  report value = 0 or (in-range? value 100 3000 and value mod 50 = 0)
end

to-report plot-time-maximum
  if active-tick-limit > 0 [ report active-tick-limit ]
  ;; Unlimited interactive runs begin with a useful window and expand in
  ;; 100-tick blocks without imposing a simulation stopping condition.
  report max (list 100 (100 * ceiling ((ticks + 1) / 100)))
end

to-report planet-state-valid?
  if xcor != pxcor or ycor != pycor [ report false ]
  if not natural-number? kingdom-id or kingdom-id > 5 [ report false ]
  if not in-range? population 0.5 1.5 [ report false ]
  if not in-range? wealth 0 100 [ report false ]
  ;; A population-weighted mean of individually bounded wealth values can exceed
  ;; 100 by a few ulps through floating-point summation (for example
  ;; 100.00000000000001).  This tolerance validates the bounded state without
  ;; changing any economic or political behavior.
  if not in-range? previous-policy-wealth -1.0E-12 (100 + 1.0E-12) [ report false ]
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
310
80
766
537
-1
-1
7.0
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

TEXTBOX
10
10
1220
42
FOUNDATION  /  Religion, trade & control
22
0.0
0

TEXTBOX
10
44
1210
65
Indirect influence across 30 external worlds. No conquest; control can be lost.
12
0.0
0

BUTTON
10
80
98
113
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
104
80
194
113
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
200
80
290
113
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

TEXTBOX
10
123
290
143
SIMULATION DURATION
13
0.0
0

SLIDER
10
147
290
180
tick-limit
tick-limit
0
3000
0.0
50
1
ticks
HORIZONTAL

TEXTBOX
10
190
290
210
MISSIONS
13
0.0
0

SLIDER
10
214
290
247
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
251
290
284
missionary-effectiveness
missionary-effectiveness
0
0.5
0.25
0.05
1
NIL
HORIZONTAL

TEXTBOX
10
293
290
313
TRADE
13
0.0
0

SLIDER
10
317
290
350
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
354
290
387
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
391
290
424
religion-trade-weight
religion-trade-weight
0
0.8
0.55
0.05
1
NIL
HORIZONTAL

TEXTBOX
10
432
290
452
KINGDOM POLITICS
13
0.0
0

SLIDER
10
456
290
489
royal-intolerance
royal-intolerance
0
1
0.5
0.05
1
NIL
HORIZONTAL

TEXTBOX
10
496
290
527
Higher intolerance lowers tolerance for influence.
11
0.0
0

TEXTBOX
10
533
290
553
ECONOMY
13
0.0
0

SLIDER
10
557
290
590
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
594
290
627
independence-effort
independence-effort
0
1
0.15
0.05
1
NIL
HORIZONTAL

TEXTBOX
10
637
290
657
VISUALIZATION
13
0.0
0

CHOOSER
10
661
290
706
view-mode
view-mode
"kingdom" "religion" "dependency" "control"
0

BUTTON
10
713
145
746
refresh view
update-appearance
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
154
713
290
747
Refresh when paused;\nno tick advances.
11
0.0
0

TEXTBOX
10
759
290
822
Cyan arrows: missionaries\nWhite squares: traders\nR = restrict; E = embargo\nBlue routes: stronger = thicker
12
0.0
0

MONITOR
310
550
418
595
Tick
ticks
0
1
11

MONITOR
424
550
532
595
Worlds / 30
controlled-planets
0
1
11

MONITOR
538
550
646
595
Kingdoms / 4
controlled-kingdoms
0
1
11

MONITOR
652
550
760
595
Routes
count trade-routes
0
1
11

MONITOR
310
602
418
647
Religion
mean-religion
3
1
11

MONITOR
424
602
532
647
Dependency
mean-dependency
3
1
11

MONITOR
538
602
646
647
Treasury (cr.)
foundation-treasury
2
1
11

MONITOR
652
602
760
647
Executions
total-executed-missionaries + total-executed-traders
0
1
11

MONITOR
310
654
418
699
Restricted
count planets with [not foundation? and policy = \"restrict\"]
0
1
11

MONITOR
424
654
532
699
Embargoed
count planets with [not foundation? and embargoed?]
0
1
11

MONITOR
538
654
646
699
Tech crises
technology-crisis-planets
0
1
11

MONITOR
652
654
760
699
Wealth [0-100]
mean-wealth
2
1
11

TEXTBOX
310
711
770
731
RELIGION: 0 red  ->  0.5 amber  ->  1 green
11
0.0
0

TEXTBOX
310
733
770
753
DEPENDENCY: dark to light blue. CONTROL: green / gray.
11
0.0
0

TEXTBOX
310
755
770
780
Gold star = Terminus; rings = capitals. R / E = policy.
11
0.0
0

PLOT
790
80
1170
235
Control over time
ticks
worlds / 30
0.0
1000.0
0.0
30.0
false
false
"set-plot-x-range 0 plot-time-maximum" "set-plot-x-range 0 plot-time-maximum"
PENS
"controlled-planets" 1.0 0 -10899396 true "" "plotxy ticks controlled-planets"

PLOT
790
246
1170
401
Religion and dependency
ticks
mean [0 - 1]
0.0
1000.0
0.0
1.0
false
true
"set-plot-x-range 0 plot-time-maximum" "set-plot-x-range 0 plot-time-maximum"
PENS
"mean-religion" 1.0 0 -10899396 true "" "plotxy ticks mean-religion"
"mean-dependency" 1.0 0 -13791810 true "" "plotxy ticks mean-dependency"

PLOT
790
412
1170
567
Religion distribution
religion (0 - 1)
worlds
0.0
1.0
0.0
30.0
false
false
"set-plot-pen-interval 0.1" ""
PENS
"worlds" 1.0 1 -10899396 true "" "histogram map [value -> min (list value (1 - 1.0E-12))] (map [world -> [religion] of world] sort planets with [not foundation?])"

PLOT
790
578
1170
733
Trade economy
ticks
credits / tick
0.0
1000.0
0.0
10.0
false
false
"set-plot-x-range 0 plot-time-maximum" "set-plot-x-range 0 plot-time-maximum set-plot-y-range 0 max (list 10 plot-y-max (10 * ceiling (trade-income-this-tick / 10)))"
PENS
"gross trade income" 1.0 0 -13791810 true "" "plotxy ticks trade-income-this-tick"

TEXTBOX
790
744
1170
768
Histogram: 10 bins; last bin includes religion = 1.
11
0.0
0

@#$#@#$#@
## WHAT IS IT?

How can the Foundation gain and retain non-military influence through Scientism,
technology and trade when independent governments can resist it? This original
agent-based model explores that question using 30 external worlds and Terminus.
Religion can help traders enter markets; trade creates dependency, while repression
can reduce influence and eventually damage an already-dependent economy. These
feedbacks may produce expansion, resistance or failure. A tipping point is a
hypothesis to investigate, not a guaranteed result or historical prediction.

## HOW TO USE IT

1. Open this file in NetLogo 6.4.x. Choose slider settings, then click **setup**.
   Simulation Duration defaults to 0 (unlimited); positive choices are
   100–3000 ticks in steps of 50.
2. Click **go-once** to advance exactly one tick. Click **go** to run continuously;
   click it again to pause. A positive duration stops exactly at the value
   captured by setup; 0 continues until you pause the run. Changing Simulation
   Duration mid-run affects only the next setup.
3. Watch the map, monitors and plots. Choose a view under **view-mode**.
   While paused, click **refresh view** to redraw without advancing time. During
   a run the view refreshes each tick. Colors and charts do not change outcomes.
4. To repeat the same run, enter `random-seed 123 setup` in the Command Center
   with the same slider settings, then run go. Setup never chooses a fixed seed
   automatically. Use different seeds to study variation.

Setup clears travelers, routes, counters, control streaks and plots and resets
time and treasury. It preserves your chosen sliders and view. Saved widget
settings are the defaults below. Sliders can also change during a run: rate
changes affect subsequent actions; the two population sliders become recruitment
targets. Lowering a target does not kill living agents. For comparisons, hold
settings fixed within each run and set them before setup.

For a finite run, the three tick-based plots use its captured duration. For an
unlimited run they expand in 100-tick blocks. The religion histogram keeps its
0–1 horizontal scale because it is a distribution, not a time series.

### Parameters (widget names and meanings)

- **tick-limit** (Simulation Duration): 0 means unlimited; finite choices are
  100–3000 ticks in steps of 50. Setup captures the selected value for the run.

- **initial-missionaries** (missionaries: initial / target): 0–40 in steps of 2;
  default 12. Free initial missionaries and the desired living count thereafter.
- **missionary-effectiveness** (conversion effectiveness): 0–0.5 in steps of
  0.05; default 0.25. Scales conversion on accepted missions, not entry chance.
- **initial-traders** (traders: initial / target): 0–40 in steps of 2; default 12. Free initial traders and the desired living count thereafter.
- **trade-attractiveness** (technology attractiveness): 0–1 in steps of 0.05;
  default 0.60. Scales sale size, benefits, dependency and revenue.
- **religion-trade-weight** (religion effect on trade): 0–0.8 in steps of 0.05;
  default 0.55. Religion's positive contribution to trader entry probability.
- **royal-intolerance** (royal intolerance): 0–1 in steps of 0.05; default
  0.50. Higher values reduce missionary entry, increase execution risk and lower
  the government's threshold for restricting Foundation influence.
- **tech-decay-rate** (technology wear / tick): 0–0.04 in steps of 0.005;
  default 0.015. Scales dependency-sensitive infrastructure wear.
- **independence-effort** (domestic substitution effort): 0–1 in steps of
  0.05; default 0.15. Scales gradual replacement by domestic alternatives.

### Reading the map and statistics

Terminus is always a gold star. Ringed worlds are capitals. Cyan arrows are
missionaries; white outlined squares are traders in every view. Travelers may
overlap on a planet. Blue routes grow brighter and thicker with strength.
Labels **R** and **E** mean restriction and embargo; a capital's label applies
to its entire kingdom. Unmarked worlds are open. Right-click a planet and inspect
its state for religion, dependency, hostility, policy, health and control streak.

- **kingdom**: Anacreon red, Smyrno blue, Konom green, Daribow purple; independent
  worlds gray. These identities remain fixed even when influence changes.
- **religion**: red at 0, amber at 0.5, green at 1; this is local Scientism
  influence, not a headcount of worshippers.
- **dependency**: dark to light blue from 0 to 1; brighter worlds depend more
  heavily on Foundation technology, regardless of religious belief.
- **control**: green means current effective control, gray means uncontrolled.
  Capitals retain rings, and Terminus is excluded from external control counts.

**Worlds / 30** counts worlds sustaining sufficient leverage for five ticks.
**Kingdoms / 4** also requires a controlled capital and a population-weighted
controlled share of at least 60%. Religion and dependency monitors are unweighted
means of the 30 external worlds on a 0–1 scale. Treasury is available credits;
executions are cumulative losses of both visitor breeds, not all rejected visits.
Routes count all live trade links. Restricted and embargoed monitors count worlds,
not governments. Technology crises count dependent worlds with damaged technology;
wealth is the external mean on a 0–100 scale.

**Control over time** plots external controlled worlds (0–30). **Religion and
dependency** plots both means on the same 0–1 scale. **Religion distribution** is
a fresh histogram of 30 worlds at each tick, using ten bins of width 0.1. The
last bin includes religion exactly 1 (the plotted input is nudged below 1 solely
to accommodate NetLogo's exclusive upper histogram bound; state is unchanged).
**Trade economy** shows gross sales credits earned during each tick, not treasury
or net profit. Its vertical scale expands to fit observed income. All plots reset
at setup, include the initial state and update once per tick. Monitors round only
the displayed values. BehaviorSpace can run with plot updates disabled; plotting
is not part of any decision rule.

## HOW IT WORKS

### ODD overview: purpose, entities and state

The purpose is to study indirect, reversible influence under political resistance.
The model has three breeds: stationary planets, traveling missionaries and traveling
traders, plus undirected trade routes. Empty patches are space. Terminus is the
Foundation's home; Anacreon, Smyrno, Konom and Daribow each contain five planets,
including one capital. Ten outer worlds have independent local governments.

Each planet stores population weight, religion, technology dependency, trust,
demand, infrastructure health, wealth, hostility, taboo, temple presence, policy,
embargo status and control persistence. Normalized attributes are in [0,1]; wealth
is [0,100]. Capitals retain a previous wealth snapshot and policy timing. Travelers
store skill, destination, mode and detention time; traders also store origin and
transaction capacity. Routes store strength and age. Global accounts track
Foundation treasury, gross tick income, net cumulative profit, visits, executions
and paid recruits. Population weights are fixed, not simulated individual people.

### Process overview and scheduling

Space is a 64 by 64 grid wrapping on both axes. One tick is an abstract interval,
not a day or year. Each tick applies environmental updates, missionary actions,
trader actions and route wear. At ticks 0, 10, 20, ... governments decide and the
Foundation recruits. Local political effects then update religion and hostility,
control is evaluated, appearance refreshes and the clock advances once. Plots
observe the resulting state. Agent execution order within each traveling breed is
randomized; governments and deterministic display updates use stable ordering.

### Design concepts

**Emergence:** routes, religious persistence, dependence, resistance and control
arise from visits and local feedback, without a timetable of historical events.
**Sensing:** travelers use observable destination attitudes, distance and route
access, not knowledge of future random outcomes. Governments aggregate their own
planets' current state and compare wealth with the preceding decision.
**Interaction:** missions convert and sometimes repair; sales replenish technology,
build trust and dependency, and connect markets. Government policies alter access,
repression and maintenance. There is no contagious neighbor-to-neighbor conversion.
**Stochasticity:** initial states and visitor skills are sampled; destinations,
admission, execution and detention are random using NetLogo's seeded RNG.
**Adaptation:** governments respond to threats and measured economic crises;
travelers reselect destinations with fixed choice rules. There is no learning or
strategic optimization. **Observation:** plots and monitors expose current state
without affecting it. Repeated seeds are needed to distinguish patterns from chance.

### Initialization and input data

No external data or extensions are required. Setup samples a new galaxy with
31 distinct stationary worlds at least three toroidal units apart. Capitals lie
at (+/-18, +/-18), their neighbors within six units, and independent worlds outside
eight-unit capital buffers. Placement retries are bounded. Kingdom membership is
fixed. All policies start open; no routes or controlled worlds exist initially.
Terminus starts with religion/trust/health 1, wealth 100, a temple, and no dependency.
Treasury starts at 200; initial travelers are free and depart from Terminus.

The duration-sweep BehaviorSpace definitions set `tick-limit` explicitly before
setup, so they are independent of the unlimited Interface default. Every other
automated definition carries a finite BehaviorSpace time limit and records its
terminal `ticks`. The baseline and extended sweeps use 450 and 1000 ticks with
the same factor grid, repetitions, reporters and run-number-based seed scheme.

External uniform ranges are religion [.02,.20), dependency [0,.08), trust [0,.10),
health [.65,.90), demand [.40,.80), wealth [40,80), taboo [0,.35), population [.5,1.5).
Kingdom hostility baselines are .60, .25, .50 and .40 respectively, with +/- .10
jitter; independent hostility is [.15,.80). These are scenario assumptions,
not canonical or measured historical facts. Visitor skill is uniform [.75,1.25).

### Submodels

### Missionaries

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

### Traders and routes

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

### Technology and economy

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

### Government, repression and control

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


## THINGS TO NOTICE / TRY

Compare several seeds at low versus high royal intolerance while holding other
settings fixed. Observe religious influence, trade and control separately: a
religious world need not be controlled, and secular trade can create dependency.
Default runs can fail to expand; this is a possible outcome, not a blank display.

Set missionaries to zero before setup to observe secular trade. Set traders to
zero to observe religion without new commercial dependency and recruitment costs
without trade revenue. Set both counts to zero to isolate environmental change.
Try 40 of each visitor, effectiveness .5, attractiveness 1, intolerance 0,
independence effort 0 and wear .005 as a favorable comparison; success is not
promised for every seed. Restore defaults before comparing default runs.

Watch dependent worlds under E labels: their wealth does not drop instantly when
sanctioned. Missing support can damage infrastructure and later trigger a crisis.
An economic concession reopens access but gives no immediate repair or wealth.
Increase independence effort to compare gradual domestic substitution. Follow a
capital's policy, wealth memory and cooldown in its inspector. Do not infer a
universal threshold or historical conclusion from one stochastic run.

## SIMPLIFICATIONS AND LIMITATIONS

The star map is fictional and early Foundation periods are deliberately blended.
There are no individual worshippers, population dynamics, fleets, warfare or
formal annexation. Toroidal travel is a modeling device, not astrophysical distance.
Credits and wealth are abstract, with no empirical fitting or conserved economy.
Planet sale benefits are net development benefits after payment; initial travelers
are free, there is no upkeep, cargo renews between visits, and domestic substitution
has no explicit investment cost. Government differences use initial hostility,
not historical scripts. The fixed leverage weights and persistence threshold define
effective influence, not legal sovereignty, and may be tested as assumptions in
future work. A longer horizon permits more visits, policy cycles, infrastructure
wear and recovery, so 450- and 1000-tick outcomes need not match even though
identically seeded runs have the same trajectory through tick 450. The model does
not implement psychohistory or predict real politics.

## EXTENDING THE MODEL

Possible future work includes an adaptive balance between religious and commercial
strategies, richer government heterogeneity, explicit investment in domestic
industry, and supply or inventory constraints on the trade network. None of these
mechanisms is implemented here. Compare extensions against the present model with
recorded settings, seeds, uncertainty and independently tested rules.

## CREDITS / REFERENCES

Original model, inspired by Isaac Asimov's *Foundation* (1951) as literary
inspiration, not quantitative evidence. Developed for Collective Intelligence,
Autumn 2026, assignment by Tamás Takács. The assignment is credited to Tamás Takács
(2026), CC BY-NC-ND 4.0. Source license: MIT, Copyright (c) 2026 G3RIG4M3R.
No Models Library simulation logic is used. Development used AI assistance for
code, documentation and verification; the student must review and understand the
model and follow any additional course disclosure requirements.

NetLogo: Wilensky, U. (1999), *NetLogo*. Center for Connected Learning and
Computer-Based Modeling, Northwestern University, Evanston, IL.
[NetLogo](https://ccl.northwestern.edu/netlogo/),
[NetLogo documentation](https://docs.netlogo.org/), and the bundled NetLogo 6.4.0
User Manual (Interface, Programming Guide / Plotting, Dictionary and BehaviorSpace).
Use this model with NetLogo 6.4.x; later file formats are not required.
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
<experiments>
  <experiment name="Foundation Baseline Sweep (450 ticks)" repetitions="20" runMetricsEveryStep="false">
    <setup>random-seed (100000 + behaviorspace-run-number) setup</setup>
    <go>go</go>
    <timeLimit steps="450"/>
    <exitCondition>ticks &gt;= active-tick-limit</exitCondition>
    <metric>control-fraction</metric>
    <metric>cumulative-trade-profit</metric>
    <metric>controlled-planets</metric>
    <metric>controlled-kingdoms</metric>
    <metric>mean-religion</metric>
    <metric>mean-dependency</metric>
    <metric>total-executed-missionaries</metric>
    <metric>total-executed-traders</metric>
    <metric>foundation-treasury</metric>
    <metric>recruitment-costs</metric>
    <metric>total-successful-trades</metric>
    <metric>ticks</metric>
    <metric>active-tick-limit</metric>
    <metric>model-valid?</metric>
    <metric>netlogo-version</metric>
    <metric>100000 + behaviorspace-run-number</metric>
    <enumeratedValueSet variable="missionary-effectiveness"><value value="0.1"/><value value="0.15"/><value value="0.2"/><value value="0.25"/><value value="0.3"/><value value="0.35"/><value value="0.4"/></enumeratedValueSet>
    <enumeratedValueSet variable="royal-intolerance"><value value="0.2"/><value value="0.3"/><value value="0.4"/><value value="0.5"/><value value="0.6"/><value value="0.7"/><value value="0.8"/></enumeratedValueSet>
    <enumeratedValueSet variable="tick-limit"><value value="450"/></enumeratedValueSet>
    <enumeratedValueSet variable="initial-missionaries"><value value="12"/></enumeratedValueSet>
    <enumeratedValueSet variable="initial-traders"><value value="12"/></enumeratedValueSet>
    <enumeratedValueSet variable="trade-attractiveness"><value value="0.6"/></enumeratedValueSet>
    <enumeratedValueSet variable="tech-decay-rate"><value value="0.015"/></enumeratedValueSet>
    <enumeratedValueSet variable="religion-trade-weight"><value value="0.55"/></enumeratedValueSet>
    <enumeratedValueSet variable="independence-effort"><value value="0.15"/></enumeratedValueSet>
    <enumeratedValueSet variable="view-mode"><value value="&quot;kingdom&quot;"/></enumeratedValueSet>
  </experiment>
  <experiment name="Foundation Extended Sweep (1000 ticks)" repetitions="20" runMetricsEveryStep="false">
    <setup>random-seed (100000 + behaviorspace-run-number) setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <exitCondition>ticks &gt;= active-tick-limit</exitCondition>
    <metric>control-fraction</metric>
    <metric>cumulative-trade-profit</metric>
    <metric>controlled-planets</metric>
    <metric>controlled-kingdoms</metric>
    <metric>mean-religion</metric>
    <metric>mean-dependency</metric>
    <metric>total-executed-missionaries</metric>
    <metric>total-executed-traders</metric>
    <metric>foundation-treasury</metric>
    <metric>recruitment-costs</metric>
    <metric>total-successful-trades</metric>
    <metric>ticks</metric>
    <metric>active-tick-limit</metric>
    <metric>model-valid?</metric>
    <metric>netlogo-version</metric>
    <metric>100000 + behaviorspace-run-number</metric>
    <enumeratedValueSet variable="missionary-effectiveness"><value value="0.1"/><value value="0.15"/><value value="0.2"/><value value="0.25"/><value value="0.3"/><value value="0.35"/><value value="0.4"/></enumeratedValueSet>
    <enumeratedValueSet variable="royal-intolerance"><value value="0.2"/><value value="0.3"/><value value="0.4"/><value value="0.5"/><value value="0.6"/><value value="0.7"/><value value="0.8"/></enumeratedValueSet>
    <enumeratedValueSet variable="tick-limit"><value value="1000"/></enumeratedValueSet>
    <enumeratedValueSet variable="initial-missionaries"><value value="12"/></enumeratedValueSet>
    <enumeratedValueSet variable="initial-traders"><value value="12"/></enumeratedValueSet>
    <enumeratedValueSet variable="trade-attractiveness"><value value="0.6"/></enumeratedValueSet>
    <enumeratedValueSet variable="tech-decay-rate"><value value="0.015"/></enumeratedValueSet>
    <enumeratedValueSet variable="religion-trade-weight"><value value="0.55"/></enumeratedValueSet>
    <enumeratedValueSet variable="independence-effort"><value value="0.15"/></enumeratedValueSet>
    <enumeratedValueSet variable="view-mode"><value value="&quot;kingdom&quot;"/></enumeratedValueSet>
  </experiment>
</experiments>
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
