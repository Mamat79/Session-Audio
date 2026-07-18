# AUDIT SESSION AUDIO

Date : 2026-07-11

## Conclusion courte

Le projet actuel est un outil Windows de preparation/restauration d'environnement audio. Ce n'est pas encore un outil de preflight media, livraison de session, manifeste audio ou comparaison de dossiers audio.

## Fonctionnement actuel

1. Lecture de `Audio-Live.apps.json`.
2. Choix d'un profil.
3. Option de simulation.
4. Sauvegarde de l'etat Windows dans `Audio-Live.state.json`.
5. Application temporaire :
   - plan d'alimentation ;
   - services ;
   - processus ;
   - cartes reseau ;
   - lancement logiciels.
6. Restauration via `Audio-Live-Restore.bat` ou bouton GUI.

## Options sensibles ajoutees

L'onglet `Securite` permet maintenant, si l'utilisateur le coche explicitement :

- de couper temporairement le pare-feu Windows ;
- de couper temporairement le scan temps reel Microsoft Defender.

Ces options sont restaurees depuis le snapshot lorsque `Restaurer` est lance.

## Risques prioritaires

| Priorite | Sujet | Risque |
|---|---|---|
| P0 | Suppression du state apres restauration partielle | Perte possible du plan de retour arriere |
| P0 | Ecriture JSON directe | Fichier corrompu si interruption pendant ecriture |
| P1 | `-Restore -Simulate` | Ambigu : la restauration passe avant la simulation |
| P1 | Absence de tests automatises | Regression possible sur profils, reseau, accents, restauration |
| P2 | Script monolithique | Maintenance difficile |
| P3 | Score de preparation de la station | Fonctionnalite non encore implementee |

## Tests realises

- Analyse syntaxique PowerShell : OK.
- Lecture JSON : OK.
- Simulation `-NoGui -Simulate` : OK, aucune action Windows appliquee dans ce mode.
- Recherche medias reels dans le dossier projet : aucun detecte.
- Recherche secrets par motifs courants : aucun detecte.

## Non teste

- Lancement reel administrateur.
- Restauration reelle.
- GUI manuelle complete.
- NAS, reseau, disque externe.
- Preflight audio, BWF, iXML, hashes, livraison : non implementes.
