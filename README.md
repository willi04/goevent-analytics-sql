# GoEvent Analytics — Nettoyage, contrôle qualité et analyse en SQL

Analyse SQL des données de **GoEvent**, la plateforme de billetterie que je développe pour la République centrafricaine ([goevent.africa](https://goevent.africa)).

L’objectif : partir d’un export brut de la base PostgreSQL, **vérifier sa qualité**, construire une **table de faits** fiable, puis décrire l’activité de la plateforme pendant sa phase de test.

> **À propos des données.** Il s’agit de l’export anonymisé de la **phase de test** (mai à juillet 2026) : 29 utilisateurs, 7 événements, 44 billets, 37 paiements. Une partie est constituée de données de démonstration (« Demo Organisation »), et les paiements Orange Money passent par l’environnement de test de l’agrégateur. Ce projet montre une **méthode** ; ses résultats décrivent cet échantillon et ne sont pas des conclusions statistiques.

## Démarche

1. **Chargement typé** (`schema.sql`) : séparateur `;`, chaînes vides converties en `NULL`, booléens `t`/`f` convertis en `1`/`0`.
2. **Staging** : copies de travail (`stg_tickets`, `stg_payments`) pour ne jamais modifier les sources, puis harmonisation des valeurs textuelles.
3. **Contrôles qualité** : intégrité référentielle, doublons de clés métier, cohérence financière, cohérence entre statuts.
4. **Table de faits** `fait_ventes` : une ligne par paiement complété, avec contrôles finaux.
5. **Analyses exploratoires** : 8 questions métier, chacune suivie de sa lecture.

## Ce que les contrôles qualité ont révélé

| Contrôle | Résultat | Conséquence |
| --- | --- | --- |
| Paiements sans billet | 0 | — |
| Billets dont l’événement est absent | **31 billets sur 44**, sur 12 événements absents de l’export | Les analyses par événement, organisateur ou catégorie ne portent que sur une partie des ventes |
| Doublons (`qr_hash`, `transaction_id`) | 0 | — |
| Règle `base_price + platform_fee = amount` | **Fausse** sur 34 paiements sur 37 | Ce n’était pas la règle métier |
| Règle `organizer_amount + platform_fee = amount` | **Vraie** sur 37 paiements sur 37 | Structure des frais retrouvée : l’acheteur paie le prix + 4 %, l’organisateur reçoit 93 %, la plateforme garde 11 % ; le cash est sans commission |
| Statut du billet ↔ statut du paiement | Cohérents | 3 billets gratuits et 4 réservations cash n’ont pas de paiement, comme attendu |
| Utilisateurs parrainés | **0 sur 29** | Importée sans `NULLIF`, la colonne vide deviendrait `0` et ferait croire que 100 % des utilisateurs sont parrainés |

Le contrôle financier est le plus instructif : la première règle testée semblait évidente et elle était fausse. C’est en confrontant l’hypothèse aux données que la vraie structure des frais est apparue.

## Ce que montrent les données

1. **Revenu concentré.** 10 paiements complétés pour 23 022 FCFA. Un seul événement représente 87 % du revenu, les deux premiers 96 %.
2. **Remplissage très faible.** Sur les 7 événements de l’export, le meilleur remplissage est de 2,5 %, et 5 n’ont vendu aucune place.
3. **Paiements non aboutis : un effet du test.** 27 % des paiements sont complétés, 51 % en attente, 22 % échoués. Mais les 19 paiements en attente viennent tous du même compte, qui totalise 23 des 27 paiements non aboutis : ce sont des essais répétés dans l’environnement de test de l’agrégateur, pas un comportement d’acheteurs.
4. **Deux usages du paiement.** 7 paiements Orange Money (panier moyen 146 FCFA) et 3 paiements cash (panier moyen 7 333 FCFA).
5. **Parrainage non mesurable.** Aucun utilisateur n’a de parrain dans l’export.
6. **Organisateurs.** Seuls 20 000 FCFA sont rattachables à un organisateur, tous à « Demo Organisation » ; les 3 022 FCFA restants portent sur des événements absents de l’export. Le revenu principal vient donc d’un événement de démonstration.
7. **Pas de récurrence.** 22 312 FCFA en mai, 312 en juin, 398 en juillet : le pic de mai correspond à l’événement de démonstration.
8. **Catégories.** Seule « Soirée » apparaît, mais 13 % du revenu porte sur des événements absents de l’export : ce résultat n’est pas généralisable.

**Synthèse.** Sur ces données, la question n’est pas encore « comment se vend GoEvent ? » mais « les données sont-elles fiables pour répondre ? ». Ce projet y répond : la chaîne de paiement est cohérente et la structure des frais est vérifiée, mais l’export est incomplet (événements manquants) et dominé par des données de test et de démonstration.

## Techniques SQL utilisées

- **Qualité des données** : anti-jointures (`LEFT JOIN … IS NULL`, `NOT EXISTS`), détection de doublons (`GROUP BY … HAVING`), contrôles de règles métier.
- **Modélisation** : table de staging, table de faits.
- **Agrégation** : `GROUP BY`, pivot avec `SUM(CASE …)`, parts en pourcentage.
- **Sous-requêtes** scalaires, dérivées et corrélées.
- **Fonctions fenêtre** : `RANK`, `ROW_NUMBER`, `LAG`, cumul avec `SUM() OVER`, `PARTITION BY`.
- **CTE** chaînées et récursive (chaîne de parrainage).

Exemple — vérification de la règle financière :

```sql
SELECT COUNT(*) AS nb_ecarts_regle_reelle
FROM stg_payments
WHERE ABS(organizer_amount + platform_fee - amount) > 0.01;   -- résultat : 0
```

## Reproduire le projet

Prérequis : MySQL 8 (ou MariaDB 10.6+), avec `local_infile` activé.

```bash
# depuis la racine du dépôt
mysql -u root -p --local-infile=1 < schema.sql
mysql -u root -p < goevent_analytics.sql
```

Le script a été exécuté de bout en bout sur MariaDB 10.11 ; les chiffres de ce README en sont issus.

## Structure du dépôt

| Fichier | Rôle |
| --- | --- |
| `schema.sql` | Création des tables et chargement typé des CSV |
| `goevent_analytics.sql` | Staging, contrôles qualité, table de faits, analyses, annexe de requêtes |
| `data_public/` | Export anonymisé (noms et e-mails remplacés) |

## Limites et suites

**Limites.** Trois mois de phase de test, faibles volumes, export partiel des événements, présence de données de démonstration.

**Suites envisagées.**
- Exporter la table `events` complète et rejouer l’analyse.
- Passer à un **schéma en étoile** (faits + dimensions événement, utilisateur, date).
- Automatiser le chargement et les contrôles qualité dans un mini-pipeline **ETL en Python**, exécuté à chaque export.

## Auteur

**Emmanuel MADOUKOU**, licencié en Mathématiques-Informatique (Université de Bangui), futur Data Engineer.
[github.com/willi04](https://github.com/willi04) · [goevent.africa](https://goevent.africa)
