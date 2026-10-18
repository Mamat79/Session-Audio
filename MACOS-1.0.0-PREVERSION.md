# Session Audio Mac 1.0.0 — préversion

Cette préversion expérimentale est distincte de Session Audio pour Windows. Elle ne remplace pas la version stable Windows et ne revendique pas la parité fonctionnelle avec Windows.

Les deux paquets sont destinés à macOS 14 ou ultérieur : Apple Silicon (`arm64`) et Intel (`x86_64`). Les applications ne disposent pas d'une signature de distribution qualifiée et ne sont pas notarisées. Aucun contournement des protections de macOS n'est fourni.

La construction Codemagic provient du commit source privé `3dc1a6eb1b9bc63972256ee6eb19b731112857ff`, job `6ad4847c39dec384b1403796`. Les sources restent privées. Le tag du dépôt public désigne un commit de documentation publique, pas ce commit source privé.

Contrôles exécutés sur le runner Apple Silicon : **26 tests XCTest du cœur** et **11 tests natifs du sous-ensemble AppKit** réussis. Les versions internes des deux applications sont `1.0.0`. Les architectures, le minimum macOS 14 et la concordance entre le contenu des DMG montés et les applications empaquetées ont été vérifiés.

Les applications empaquetées **n'ont pas été lancées ni installées** pendant cette qualification. La recette graphique complète, l'exécution sur un Mac Intel physique et l'exécution sur macOS 14 restent à faire. Les 11 tests AppKit ne valent pas validation de toute l'interface ni du lancement par LaunchServices.

Le port Mac ne réalise pas les optimisations système de Session Audio Windows. Il conserve le statut de préversion et ne doit pas être présenté comme une version stable ou une validation du comportement Windows.

| Paquet | Taille | SHA-256 |
|---|---:|---|
| `Session-Audio-Mac-1.0.0-arm64-unsigned.dmg` | 200 843 octets | `f992412c226fc671c9528ddcfcd79db7bcb771523bdd42dd4a00fc7e98836668` |
| `Session-Audio-Mac-1.0.0-x86_64-unsigned.dmg` | 202 582 octets | `325470a6b072cdd924bd4067a14d63d0e2c2d7a5308d1a5c4ee4bad35cd69035` |

Chaque DMG est accompagné d'un fichier `.dmg.sha256` portable contenant uniquement l'empreinte et le nom du DMG correspondant. Les journaux, rapports internes de qualification et sources privées ne font pas partie de la livraison publique.
