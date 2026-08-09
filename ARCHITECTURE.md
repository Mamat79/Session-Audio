# ARCHITECTURE

## Etat actuel

Le projet est principalement compose d'un script PowerShell WinForms :

- `Audio-Live.ps1` : interface, configuration, actions Windows, restauration, diagnostic ;
- `Audio-Live.apps.json` : profils et listes d'elements geres ;
- `Audio-Live-Launch.bat` : lancement administrateur ;
- `Audio-Live-Restore.bat` : restauration directe ;
- `Mode_Audio.pow` : plan d'alimentation importable ;
- `SessionAudioLauncher.exe` : lanceur natif compile, eleve en administrateur ;
- `installer/SessionAudio.iss` : definition de l'installeur Inno Setup ;
- `Build-Installer.ps1` : build reproductible et creation du checksum ;
- `Test-Installer.ps1` : installation, simulation et desinstallation dans un dossier temporaire.

La configuration utilisateur `Audio-Live.apps.json` n'est pas versionnee. Le depot conserve uniquement `Audio-Live.apps.example.json`, dont tous les choix sensibles sont desactives.

## Flux

1. Lire la configuration.
2. Afficher l'interface ou utiliser `-NoGui`.
3. En simulation : ecrire le plan sans action.
4. En lancement : sauvegarder l'etat precedent.
5. Appliquer plan, services, processus, reseau, securite si demandee.
6. Lancer les applications.
7. Restaurer via `Audio-Live.state.json`.

## Distribution Windows

1. Compiler le lanceur C# avec le compilateur .NET Framework fourni par Windows.
2. Exporter une configuration de demarrage sure.
3. Compiler l'installeur Inno Setup.
4. Installer dans un dossier temporaire sans raccourcis.
5. Verifier la syntaxe, le JSON, la simulation et la desinstallation.
6. Publier l'installeur et son SHA-256 dans une release GitHub privee.

## Dette technique

`Audio-Live.ps1` reste monolithique. Extraction progressive recommandee :

- configuration ;
- etat/restauration ;
- actions Windows ;
- interface ;
- diagnostic ;
- score de preparation.

Ne pas reecrire tout d'un coup.
