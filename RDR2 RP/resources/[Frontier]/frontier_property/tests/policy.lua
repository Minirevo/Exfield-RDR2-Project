local policy = {}
exports = function(name, fn) policy[name] = fn end
local root = ... or '.'
dofile(root .. '/config.lua')
dofile(root .. '/server/policy.lua')
local calculate = policy.CalculateForeclosure
local build, sell, furnish = policy.CanBuildUnderPropertyPolicy, policy.CanSellUnderPropertyPolicy,
    policy.CanTenantFurnishUnderPropertyPolicy
assert(build(0, false) and not build(1, false) and not build(0, true) and not build(0))
assert(sell(0, false, true) and sell(0, true, true, true))
assert(not sell(1, false, true) and not sell(0, false, false) and not sell(0, true, true))
assert(furnish(true, true) and not furnish(true, false) and not furnish(false, true))
local normal = assert(calculate(100000, 20000))
assert(normal.deductionCents == 30000 and normal.debtPaidCents == 20000)
assert(normal.statePenaltyCents == 25000 and normal.ownerPayoutCents == 25000)
assert(normal.debtForgivenCents == 0)
local short = assert(calculate(100000, 80000))
assert(short.debtPaidCents == 70000 and short.debtForgivenCents == 10000)
assert(short.statePenaltyCents == 0 and short.ownerPayoutCents == 0)
local odd = assert(calculate(3, 0))
assert(odd.statePenaltyCents == 1 and odd.ownerPayoutCents == 2)
assert(calculate(-1, 0) == nil and calculate(1, 0.5) == nil)
PropertyConfig.ForeclosureDeductionBps = 10000
assert(calculate(10000, 400).debtForgivenCents == 400)
PropertyConfig.ForeclosureStatePenaltyBps = 10001
assert(calculate(10000, 400) == nil)
print('Property policy passed')
