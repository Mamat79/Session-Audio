# CHANGELOG

## 2026-07-13

- Ajout d'une option pour suspendre temporairement les taches planifiees Microsoft Defender.
- Le diagnostic liste maintenant l'etat des taches Defender.
- La restauration remet les taches Defender dans leur etat precedent lorsque Windows l'autorise.
- Documentation mise a jour pour clarifier que le service Defender protege par Windows n'est pas force.

## 2026-07-11

- Ajout de `.gitignore`.
- Ajout des rapports et documents de cadrage :
  - `CLEANUP_REPORT.md`
  - `AUDIT_SESSION_AUDIO.md`
  - `DRY_RUN.md`
  - `PREFLIGHT.md`
  - `MANIFEST_FORMAT.md`
  - `DELIVERY_WORKFLOW.md`
  - `TESTING.md`
  - `BENCHMARKS.md`
  - `KNOWN_LIMITATIONS.md`
- Aucune suppression de fichier.
- Aucun media reel modifie.
- Aucun depot Git initialise.

## 2026-07-12

- Clarification du perimetre : Session Audio prepare le poste Windows, sans analyse de fichiers audio.
- Ajout de l'onglet `Securite`.
- Ajout des options sensibles, decochees par defaut :
  - couper temporairement le pare-feu Windows ;
  - couper temporairement le scan temps reel Microsoft Defender.
- Sauvegarde/restauration de l'etat pare-feu et Defender dans `Audio-Live.state.json`.
- Blocage de ces options en mode `-NoGui` hors simulation.
- Mise a jour des documents :
  - `SECURITY.md`
  - `WINDOWS_ACTIONS.md`
  - `RESTORE.md`
  - `PROFILES.md`
  - `READINESS_SCORE.md`
  - `APPLICATION_ADAPTERS.md`
  - `ARCHITECTURE.md`
