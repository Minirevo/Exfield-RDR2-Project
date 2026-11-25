# Temporary farming model lab

Standalone RedM test resource. No SQL, inventory, economy, or property changes. No networked preview entities. Only one local preview per tester.

## Install
Copy this folder into resources. Add the following ACE temporarily (or grant it to your specific tester principal):
```cfg
add_ace group.admin frontier.farmmodels allow
ensure frontier_farm_modeltest
```
Run /farmmodels in game as an authorized player. Select a candidate or enter any exact model name. The candidate list is exploratory, **not a verified catalogue**. Invalid models and loading failures are reported. Move/rotate/ground-align the object or scale animal peds. Generic prop scaling is deliberately not implemented because it is not reliably supported. Use Walk around preview to inspect and /farmmodels to reopen without replacing the current preview. Copy recorded test notes before stopping the resource.

Test on flat terrain and inspect several crop models, fences, troughs, wells and animals. Verify appearance, collisions, dimensions and whether animal scaling works. Preview entities are frozen and invincible, not production livestock AI.

## Removal
Run stop frontier_farm_modeltest, remove the ensure and temporary ACE from server.cfg, then delete this folder. No database cleanup needed. Closing the UI or stopping the resource deletes its preview. No production resources have been modified.

## Medium cattle pen preview
On flat terrain, stand facing a clear area at least 12 x 16 m and run /farmpen. The assembly is centered 14 m ahead. /farmpen rotate rotates it 90 degrees around its center, /farmpen clear removes all parts. Same ACE as the model lab. Local frozen previews only. 26 fence segments, four furnishing props and three representative cattle (33 entities). Open 4 m entrance; no gate or shelter until suitable models are verified. Each part samples terrain separately; sloped ground may cause fence gaps. No changes to the HTML candidate list.
