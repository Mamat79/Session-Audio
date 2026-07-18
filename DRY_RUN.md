# DRY RUN

## Etat actuel

Le script possede deja un mode simulation :

```powershell
.\Audio-Live.ps1 -NoGui -Simulate
```

Ce mode produit un plan de session audio sans appliquer les changements Windows.

## Ce que le dry-run actuel couvre

- Plan d'alimentation choisi.
- Logiciels selectionnes.
- Services selectionnes.
- Processus selectionnes.
- Adaptateurs reseau selectionnes.
- Alerte si `Audio-Live.state.json` existe.

## Ce qui manque encore pour un dry-run poste complet

- Rapport Information / Avertissement / Erreur / Erreur bloquante.
- Confirmation obligatoire avant execution reelle de copie.
- Plan detaille action par action avec droits requis.
- Score de preparation du poste.
- Liste explicite des options sensibles : reseau, pare-feu, Defender.

## Regle cible

Aucune execution reelle du profil ne doit commencer sans :

1. rapport dry-run genere ;
2. erreurs bloquantes corrigees ;
3. confirmation explicite utilisateur ;
4. snapshot de restauration disponible.
