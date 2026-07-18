# ARCHITECTURE

## Etat actuel

Le projet est principalement compose d'un script PowerShell WinForms :

- `Audio-Live.ps1` : interface, configuration, actions Windows, restauration, diagnostic ;
- `Audio-Live.apps.json` : profils et listes d'elements geres ;
- `Audio-Live-Launch.bat` : lancement administrateur ;
- `Audio-Live-Restore.bat` : restauration directe ;
- `Mode_Audio.pow` : plan d'alimentation importable.

## Flux

1. Lire la configuration.
2. Afficher l'interface ou utiliser `-NoGui`.
3. En simulation : ecrire le plan sans action.
4. En lancement : sauvegarder l'etat precedent.
5. Appliquer plan, services, processus, reseau, securite si demandee.
6. Lancer les applications.
7. Restaurer via `Audio-Live.state.json`.

## Dette technique

`Audio-Live.ps1` reste monolithique. Extraction progressive recommandee :

- configuration ;
- etat/restauration ;
- actions Windows ;
- interface ;
- diagnostic ;
- score de preparation.

Ne pas reecrire tout d'un coup.

