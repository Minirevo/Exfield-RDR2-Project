# Frontier Damage Laboratory (development only)

Purpose: determine which RedM injury signals survive native health protection. No medical, inventory, economy, character or respawn code is changed. The lab never cancels damage events or revives a dead player. Do not deploy or enable on a public server.

## Setup (private test instance)
Use a disposable test character, preferably back up DB. Stop frontier_medical and frontier_needs and keep vorp_medic and vorp_metabolism stopped. This temporarily disables medical/needs gameplay and profession labour checks; VORP Core stays running and native death can still trigger its respawn system. The lab refuses to start if any conflicting resource is running. It uses the existing VORP Core DataView helper only for event decoding.

Add to the TEST server.cfg:
```cfg
set frontier_damagelab_enabled 1
add_ace group.admin frontier.damagelab allow
ensure frontier_damagelab
```
Ensure your test account actually belongs to group.admin or grant the ACE to your existing admin principal. Default convar is off; every trial requires server ACE permission. The server revokes trials on timeout/disable/conflict and client independently checks timeout/session/resource changes. No automatic trials, no SQL.

## Modes
- /damagelab observe: unchanged native health; baseline. Can die.
- /damagelab refill: sample every rendered frame, record health deltas before restoring ordinary max health. Can still die from a lethal hit.
- /damagelab buffer: try a 5000 raw max-health buffer and refill every frame, measuring actual deltas. Can still die if engine bypasses the buffer.
- /damagelab guarded: buffer + ped config flags 263 (no critical hits), 340 (disable melee takedowns), 388 (disable fatally wounded behaviour). These are experimental RDR3 flags; they may alter animations or damage signals. Not a promise of death prevention.
- /damagelab invincible: native player invincibility only, for comparison; inspect which events remain visible. May suppress all damage.
- /damagelab off: stop; restore prior max health, health (if still alive), flags and invincibility. Switching modes, leaving character, death, expiry and resource stop also clean up. A native/host crash cannot guarantee cleanup; reconnect on the test server if necessary.
- /damagelabmark npc-punch: add a label to subsequent logs. /damagelabstatus shows counters/remaining time. Trial lasts 180 seconds. Full logs in F8, summary in server console. Do not count multiple native signals as multiple hits.

## Test protocol
Start with observe, then refill, then guarded, then invincible, optionally buffer to isolate flags. Use the same kind of attack in each trial; start with one NPC punch, then repeated punches/knockdown, then a gunshot, fall, animal attack, fire, drowning. Mark each case before it starts. Record whether animations/knockdowns happen and whether native death occurs. When a mode dies, respawn using existing VORP flow before starting another. Prefer a fresh healthy test character. Stop the trial before changing test conditions if you need isolated counters. After testing remove the cfg lines, stop frontier_damagelab, restart frontier_needs and frontier_medical in that order.

## Output interpretation
HEALTH_LOSS is raw engine HP difference, not a percentage of the artificially inflated buffer. AI_DAMAGE reads EVENT_ENTITY_DAMAGED (group 0, nine slots), NET_DAMAGE reads EVENT_NETWORK_DAMAGE_ENTITY (group 1, 32 slots), NET_INCAP and AI_DESTROYED are separate observations; GAME_EVENT records matching victim events, and server weaponDamageEvent is observational only. Each queue dump logs raw signed 32-bit values and a candidate float amount; fields and availability may vary by build. Counters are samples, not deduplicated attacks. Unknown/missing events do not prove that no damage occurred. The buffer/flags are deliberately diagnostic, not an authoritative gameplay solution. Native damage/death protection, event availability, layout and cleanup require live validation.
Reference: https://github.com/femga/rdr3_discoveries/tree/master/AI/EVENTS and https://github.com/femga/rdr3_discoveries/tree/master/AI/CPED_CONFIG_FLAGS .
Standalone pure helper test: lua5.4 tests/rules.lua. No production medical changes in this PR.

Troubleshooting: the server now logs a separate `Client START` acknowledgement once setup succeeds. Result includes matching trial ID, stop reason and last diagnostic error; absent optional natives are logged as nil rather than terminating a trial. Compare only matching trial IDs. If guarded fails, send the exact flag number or wanted/actual health value from the result.


## Controlled NPC trials
Once Client START is confirmed, stand on flat open ground and run:
- /damagelabnpc melee — unarmed human.
- /damagelabnpc knife — same human with knife.
- /damagelabnpc revolver — same human with revolver.
- /damagelabnpc wolf — wolf.
- /damagelabnpc stop or /damagelabnpc clear — cancel pending spawn and delete attacker, without ending health trial.

Only one attacker at a time; a new spawn replaces the previous attacker. Server checks trial ID, START acknowledgement, ACE, isolation and expiry. Model load and ground probe have deadlines. The ped is client-local to avoid OneSync entity lockdown and replication problems; other players will not see the attacker, and this cannot validate network-only damage events. The explicit attack task targets the tester only, but local ambient AI can react to it. No global relationship groups are changed. NPC is cleared when trial ends, player dies, attacker dies or moves beyond 30m, resource stops or mode switches; failed deletions retry while the resource runs. The log marks npc-melee, npc-knife, npc-revolver or npc-wolf automatically. F8 and server console report spawn/weapon/ground failures. Native model loading, AI combat and cleanup remain live tests. If attacker does not fight, report NPC spawn and damage logs.
