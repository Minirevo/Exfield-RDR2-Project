# Building asset review

The [RDR3 interior coordinate dataset](https://github.com/femga/rdr3_discoveries/blob/master/interiors/interiors_coords_and_hashes.lua)
locates interiors fixed to the map. The [object dataset](https://github.com/femga/rdr3_discoveries/blob/master/objects/object_list.lua)
proves model identifiers exist. It does not establish arbitrary placement, collision, streaming or good interior access.
The RDR3 dataset calls out that some rooms require IMAP files. The runtime for the candidate selection is RedM.
No model/interior pair was validated live for the new construction catalogue.

| Category | Candidate | Exterior evidence | Interior evidence and tentative class | Placement decision |
| --- | --- | --- | --- | --- |
| Small cabin | Ambarino cabin | Fixed world anchor. No standalone exterior confirmed. | `adl_cabin01_int` (28162); A candidate at original site | Needs isolated teleport prototype and exterior pairing. |
| Large cabin | Watson’s cabin | `wat_main_cabin`, 0x56F89CCF | `wat_cabin_int` (53250); A candidate, B via tested instancing | Exterior collision, relocated placement and all access tests pending. |
| Farmhouse | Dairyl farm | Fixed world anchor. No standalone exterior confirmed. | `dai_farmhouse01_int` (13826); A candidate | Requires suitable exterior asset and a validated separate interior. |
| Ranch house | Ranch residential shell | No paired canonical raw model and verified room found in the reviewed candidates | Unclassified | Keep disabled while sourcing an exterior/room pair. |
| Warehouse | Industrial depot | Fixed freight/industrial archetypes need an exterior pairing | Unclassified | No functional storage room and collision pairing verified. |
| Stable | Blackwater carriage house | Fixed world anchor. No relocatable full exterior confirmed. | `bla_carriagehouse_int` (53506); A candidate | Validate entry, horse clearance and collisions first. |
| Workshop | Pronghorn workshop | Fixed map anchor. No confirmed standalone equivalent. | `pro_workshop_int` (5122); A candidate | Requires placement asset and workstation acceptance checks. |
| Hunting lodge | Veteran's house | Fixed world anchor. No standalone external model verified. | `vet_house_int` (2306); A candidate | Requires a complete exterior and dedicated room test. |
| Extra candidate | Shelter | `mp001_p_mp_tent_leento03x`, 0x1FDFBAA4 | C, no enclosed usable interior | Not offered for new construction. |
| Extra candidate | Small shack | `sba_shack_b_a`, 0xC69C2521 | C for current unpaired catalogue | Not offered until an independently usable room is verified. |

An A candidate denotes an exterior location with a named world room, with live access still unverified.
A possible B integration uses a verified room anchor and a routing bucket per built property, guarded by
server access and leave/restart handling. This proposal has no release-eligible models yet. Test
spawning at owned coordinates, rotations, collision, each exterior stage, model identity, entry/exit,
two simultaneous visitors, isolation between two properties, furniture placement and persistence.
