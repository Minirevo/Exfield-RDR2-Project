FrontierMedicalConfig={
 tickMs=5000, max=1000, downBlood=350,wakeBlood=450,downPain=900,wakePain=700,
 bloodRecovery=3,painRecovery=4,woundRecovery=2,bandageStrength=60,
 treatmentMs=5000,viewMs=120000,reach=3.0,tonicSeconds=180,tonicRelief=300,
 maxDamageReport=60,
 -- Guarded mode parameters established in the development lab.
 nativeBuffer=5000,nativeFlags={263,340,388},stateTimeoutMs=15000,guardRetryMs=5000,guardStartupMs=1500,
 reportInterval=500,reportRetryMs=1200,reportMinMs=350,maxRawGroup=2000,maxRawBatch=8000,maxGroups=56,
 rawPerWound=3,traumaPerRaw=4,downTrauma=650,wakeTrauma=450,traumaRecovery=8,
 downOxygen=350,wakeOxygen=650,drowningPerReport=75,oxygenRecovery=100,drowningQuietSeconds=5,
 drowningRawThreshold=250,deprivationPerPct=10,downDeprivation=850,wakeDeprivation=650,deprivationRecovery=10,
 regions={'head','chest','abdomen','left_arm','right_arm','left_leg','right_leg'},
 -- RDR3 bone tags; unrecognized hit bones are recorded as unspecified chest trauma.
 bones={ [21030]='head',[14283]='head',[55120]='head',[14410]='chest',[14411]='chest',[14412]='chest',[14413]='chest',[56200]='abdomen',[45454]='left_arm',[53675]='left_arm',[34606]='left_arm',[54890]='right_arm',[54187]='right_arm',[22798]='right_arm',[65478]='left_leg',[55149]='left_leg',[45465]='left_leg',[6884]='right_leg',[43312]='right_leg',[33646]='right_leg' },
 items={bandage='Bandage',splint='Splint',tonic='Pain tonic'}
}
