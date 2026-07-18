# Session Audio

Outil Windows PowerShell/WinForms pour preparer temporairement un PC a une session audio et restaurer l'etat precedent.

## Lancement

Utiliser :

- `Audio-Live-Launch.bat`
- `Session Audio.lnk`

Restauration directe :

- `Audio-Live-Restore.bat`
- `Session Audio - Restaurer.lnk`

## Fonctions actuelles

- profils ;
- plan d'alimentation ;
- services Windows ;
- processus ;
- cartes reseau ;
- carte audio a conserver ;
- options securite temporaires avec confirmation ;
- simulation ;
- diagnostic ;
- restauration.

## Limite importante

Ce projet ne lit pas, ne copie pas et n'analyse pas les fichiers audio. Il sert a preparer le poste Windows pour travailler en audio, puis a revenir a un mode bureau normal.

## Securite

L'onglet `Securite` peut demander, volontairement et avec confirmation, de couper temporairement :

- le pare-feu Windows ;
- le scan temps reel Microsoft Defender ;
- les taches planifiees Microsoft Defender.

Ces options sont decochees par defaut. L'etat precedent est sauvegarde dans `Audio-Live.state.json` et restaure avec `Restaurer`.

## Documents

- `CLEANUP_REPORT.md`
- `AUDIT_SESSION_AUDIO.md`
- `DRY_RUN.md`
- `PREFLIGHT.md`
- `MANIFEST_FORMAT.md`
- `DELIVERY_WORKFLOW.md`
- `TESTING.md`
- `BENCHMARKS.md`
- `KNOWN_LIMITATIONS.md`
- `ARCHITECTURE.md`
- `SECURITY.md`
- `WINDOWS_ACTIONS.md`
- `RESTORE.md`
- `PROFILES.md`
- `READINESS_SCORE.md`
