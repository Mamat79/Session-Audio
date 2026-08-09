# Session Audio 1.0.0

Outil Windows PowerShell/WinForms pour preparer temporairement un PC a une session audio et restaurer l'etat precedent.

## Installation recommandee

Telecharger `Session-Audio-Setup-1.0.0.exe` depuis la [derniere release privee](https://github.com/Mamat79/Session-Audio/releases/latest), puis lancer l'installeur.

L'installeur :

- installe le logiciel dans le profil Windows de l'utilisateur ;
- cree les raccourcis de lancement, restauration et configuration ;
- propose un raccourci sur le Bureau ;
- conserve la configuration lors des mises a jour ;
- refuse la desinstallation tant qu'une restauration est en attente.

Voir `INSTALLATION.md` pour les details.

## Mode portable

Utiliser :

- `Audio-Live-Launch.bat`

Restauration directe :

- `Audio-Live-Restore.bat`

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

La configuration propre au PC reste dans `Audio-Live.apps.json` et n'est pas publiee dans Git. Le depot contient `Audio-Live.apps.example.json`, neutralise pour une premiere installation sure.

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
- `INSTALLATION.md`
