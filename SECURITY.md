# SECURITY

## Principe

Session Audio peut modifier temporairement certaines protections uniquement si l'utilisateur le demande explicitement dans l'onglet `Securite`.

Options disponibles :

- couper temporairement le pare-feu Windows ;
- couper temporairement le scan temps reel Microsoft Defender ;
- suspendre temporairement les taches planifiees Microsoft Defender.

Ces options sont decochees par defaut et demandent confirmation avant lancement reel.

L'installeur force aussi ces trois options a `false` dans toute nouvelle configuration distribuee, meme lorsqu'un build personnel reprend la liste locale des applications et profils.

## Restauration

Avant application, Session Audio sauvegarde :

- etat de chaque profil de pare-feu Windows ;
- etat `DisableRealtimeMonitoring` de Microsoft Defender ;
- etat des taches planifiees Microsoft Defender.

Le bouton `Restaurer` remet ces etats lorsque Windows autorise l'operation.

## Limites

- Certains antivirus tiers ne sont pas pilotables proprement par PowerShell.
- Microsoft Defender peut refuser une modification si une protection Windows l'empeche.
- Session Audio ne force pas l'arret du service Defender protege par Windows ; il journalise les refus au lieu de pretendre que l'action a reussi.
- En mode `-NoGui`, les options securite sensibles ne peuvent pas etre appliquees.
- L'installeur et le lanceur ne sont pas signes par un certificat de signature de code. Windows SmartScreen peut donc afficher un avertissement tant qu'aucun certificat n'est configure.

## Recommandation

N'utiliser ces options que pour une session maitrisee, idealement hors Internet, puis restaurer en fin de session.
