# KNOWN LIMITATIONS

- Pas de depot Git detecte dans le dossier actif.
- Pas de tag/commit/push possible sans initialiser un depot.
- Pas d'analyse audio WAV/BWF/iXML : volontairement hors perimetre.
- Pas de livraison media : volontairement hors perimetre.
- Pas de comparaison de sessions/dossiers : volontairement hors perimetre.
- Restauration reelle non retestee pendant cette passe.
- Le script principal reste monolithique.
- Les logs sont configures en `..\Logs`, donc hors dossier projet.
- `Audio-Live.state.json` existe : une ancienne session n'a pas ete restauree.
- Options pare-feu/Defender dependantes des droits administrateur et des protections Windows.
