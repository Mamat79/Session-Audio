# RESTORE

La restauration lit `Audio-Live.state.json`.

Elements restaures :

- plan d'alimentation actif avant session ;
- hibernation ;
- services geres ;
- adaptateurs reseau geres ;
- processus qui etaient ouverts si leur chemin est connu ;
- pare-feu Windows ;
- scan temps reel Microsoft Defender ;
- taches planifiees Microsoft Defender.

Si Windows refuse une restauration, l'erreur est ecrite dans le journal.

Ne pas supprimer manuellement `Audio-Live.state.json` tant que le poste n'est pas revenu dans l'etat attendu.
