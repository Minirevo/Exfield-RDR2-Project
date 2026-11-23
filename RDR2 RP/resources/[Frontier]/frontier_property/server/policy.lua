local function validMoney(value)
    return math.type(value) == 'integer' and value >= 0 and value <= 9007199254740991
end

local function validRate(value)
    return math.type(value) == 'integer' and value >= 0 and value <= 10000
end

-- Round deductions down to whole cents; each remaining cent stays with the owner.
local function calculateForeclosure(assetValue, debt)
    local deductionRate = PropertyConfig.ForeclosureDeductionBps
    local penaltyRate = PropertyConfig.ForeclosureStatePenaltyBps
    if not validMoney(assetValue) or not validMoney(debt) then return nil, 'invalid_amount' end
    if not validRate(deductionRate) or not validRate(penaltyRate) then return nil, 'invalid_rate' end

    local available = assetValue - assetValue * deductionRate // 10000
    local paid = math.min(debt, available)
    local surplus = available - paid
    local penalty = surplus * penaltyRate // 10000
    return {
        assetValueCents = assetValue,
        deductionCents = assetValue - available,
        debtPaidCents = paid,
        debtForgivenCents = debt - paid,
        statePenaltyCents = penalty,
        ownerPayoutCents = surplus - penalty,
    }
end

exports('CalculateForeclosure', calculateForeclosure)

local function canBuild(debt, activeLease)
    return validMoney(debt) and debt == 0 and activeLease == false
end

local function canSell(debt, activeLease, allOwnersApproved, buyerAcceptedLease)
    return validMoney(debt) and debt == 0 and allOwnersApproved == true
        and (activeLease == false or (activeLease == true and buyerAcceptedLease == true))
end

local function canTenantFurnish(activeLease, explicitPermission)
    return activeLease == true and explicitPermission == true
end

exports('CanBuildUnderPropertyPolicy', canBuild)
exports('CanSellUnderPropertyPolicy', canSell)
exports('CanTenantFurnishUnderPropertyPolicy', canTenantFurnish)
