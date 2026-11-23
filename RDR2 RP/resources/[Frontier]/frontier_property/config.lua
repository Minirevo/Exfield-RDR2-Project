PropertyConfig = {
    -- Keyed by name. Set boundary, exclusions, and priceCentsPerSquareMeter per staging zone.
    SurveyZones = {},
    SurveyMinArea = 25,
    SurveyMaxArea = 2500,
    ForeclosureDeductionBps = 3000,
    ForeclosureStatePenaltyBps = 5000,

    -- Candidates for a RedM placement smoke test. No spawning is enabled here.
    PropCandidates = {
        bed = 'p_bed01x',
        chest = 'p_chest01x',
        cupboard = 'p_armoir04x',
        furnace = 'p_mp_furnace01x',
        carpentryTable = 'p_sawbucktable01x',
    },
}
