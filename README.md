# GoEvent Analytics — Nettoyage & analyse de données en SQL

Projet d'analyse de données SQL mené sur les données réelles de **GoEvent Africa**, une plateforme de billetterie événementielle que j'ai conçue et déployée en République Centrafricaine (goevent.africa).

L'objectif : partir des données brutes d'exploitation, les **nettoyer et fiabiliser**, construire une **table de faits analytique**, puis en extraire des **enseignements métier** sur l'activité de la plateforme en phase de lancement.

---

## Objectif du projet

- Nettoyer des données de production brutes (valeurs manquantes, incohérences, doublons, orphelins).
- Construire une table de faits propre (`fait_ventes`) prête pour l'analyse.
- Réaliser une analyse exploratoire (EDA) et en tirer des enseignements métier exploitables.

## Données

Quatre tables issues de la base de production PostgreSQL de GoEvent, exportées puis analysées sous MySQL :

| Table | Contenu |
|-------|---------|
| `users` | Utilisateurs (fans, organisateurs, staff), avec chaînage de parrainage |
| `events` | Événements : titre, catégorie, capacité, places vendues, organisateur |
| `tickets` | Billets : statut de paiement, canal, horodatage, événement, acheteur |
| `payments` | Paiements : montant, commission, part organisateur, statut, transaction |

## Démarche

1. **Staging** — copies de travail (`stg_tickets`, `stg_payments`) pour ne jamais altérer les données sources.
2. **Nettoyage** — conversion des booléens, gestion des valeurs manquantes, contrôles de cohérence.
3. **Détection d'anomalies** — orphelins (jointures orphelines) et doublons de clés métier.
4. **Construction de `fait_ventes`** — jointure sélective, une ligne par paiement complété.
5. **Contrôles qualité** — vérifications prouvant l'absence de NULL, de doublons et d'incohérences.
6. **Analyse exploratoire (EDA)** — 8 analyses métier, chacune assortie d'un enseignement.

## Nettoyage des données (Data Cleaning)

- Tables de **staging** pour préserver les données originales.
- Conversion des **booléens** exportés en texte (`'t'`/`'f'` → `1`/`0`).
- Uniformisation des chaînes **vides en `NULL`** (`NULLIF`).
- Contrôle de **cohérence financière** : `base_price + platform_fee = amount`.
- Détection des **orphelins** via `LEFT JOIN ... IS NULL` (paiements sans billet, billets sans événement).
- Détection des **doublons** de clés métier via `GROUP BY ... HAVING COUNT(*) > 1` (`qr_hash`, `transaction_id`).
- **Standardisation** (`LOWER`, `TRIM`).
- Construction de la **table de faits** `fait_ventes` : une ligne par paiement complété.
- **Contrôles qualité finaux** : aucun montant nul ou négatif, aucune date manquante, aucun doublon.

## Principaux enseignements

> Les données correspondent à la **phase bêta** de la plateforme ; les volumes sont faibles et les conclusions sont donc à lire comme des **tendances d'amorçage**, non comme des lois établies.

1. **Revenu extrêmement concentré.** L'événement le plus performant génère à lui seul **87 %** du chiffre d'affaires, et le top 2 en cumule **96 %**. L'activité repose sur un unique événement.

2. **Remplissage quasi nul.** Le meilleur taux de remplissage atteint **2,5 %**, et **5 événements sur 7 n'ont vendu aucune place**, malgré des capacités importantes (jusqu'à 1 000 sièges). Le défi n'est pas logistique mais d'**acquisition**.

3. **Tunnel de paiement défaillant.** Seuls **27 %** des paiements aboutissent ; **51 %** restent en attente et **22 %** échouent. Près de trois tentatives sur quatre ne se concrétisent pas — un levier de revenu majeur.

4. **Deux usages de paiement distincts.** Orange Money domine en volume mais avec un très petit panier moyen (~146), tandis que le cash, minoritaire, porte les gros montants (~7 333). Le paiement mobile semble concentrer les blocages observés en (3).

5. **Base recrutée à 100 % par parrainage.** Tous les utilisateurs ont un parrain : en l'absence de groupe témoin, et avec seulement 3 acheteurs réels, l'effet du parrainage sur la dépense **n'est pas mesurable** à ce stade. La plateforme s'est amorcée par bouche-à-oreille.

6. **Organisateurs.** _(à compléter avec le résultat de la requête B6)_

7. **Aucune récurrence du revenu.** Le chiffre d'affaires s'est effondré de **98 %** après le premier mois (22 312 → 312), puis est resté au plancher. Le revenu provient d'un **pic unique**, non reproduit.

8. **Concentration sur une seule catégorie.** Seule la catégorie « Soirée » a généré du revenu ; toutes les autres (concert, sport, conférence…) sont à zéro.

**Synthèse.** GoEvent, en phase bêta, a validé sa capacité à **encaisser** un événement premium (payé en cash), mais doit encore relever trois défis pour décoller : **remplir** ses événements, **fiabiliser le paiement mobile**, et **générer des revenus récurrents**.

## Compétences techniques mobilisées

- **Jointures** multi-tables, anti-jointures et semi-jointures.
- **Sous-requêtes** : scalaires, dérivées, corrélées.
- **Agrégation** : `GROUP BY`, `HAVING`, pivot avec `SUM(CASE ...)`, parts en pourcentage.
- **Fonctions fenêtre** : `RANK`, `LAG`, cumul (running total), `PARTITION BY`.
- **CTE** (`WITH`), y compris **récursive** (chaîne de parrainage).
- **Qualité des données** : détection d'orphelins et de doublons, contrôles de cohérence.
- **Modélisation** : construction d'une table de faits.

## Exemple de requête — chaîne de parrainage (CTE récursive)

```sql
WITH RECURSIVE chaine_parrainage AS (
  SELECT id, full_name, referred_by_user_id, 0 AS nv_profondeur
  FROM users
  WHERE id = 30
  UNION ALL
  SELECT u.id, u.full_name, u.referred_by_user_id, c.nv_profondeur + 1
  FROM users u
  JOIN chaine_parrainage c ON u.referred_by_user_id = c.id
)
SELECT * FROM chaine_parrainage WHERE nv_profondeur > 0;
```

## Structure du dépôt

- `goevent_analytics.sql` — script complet, commenté : nettoyage, table de faits et analyses.
- `README.md` — ce document.

## Limites & suites

**Limites.** Données de phase bêta (faibles volumes), 3 mois d'historique, base entièrement parrainée sans groupe témoin. Les enseignements sont des tendances d'amorçage.

**Suites envisagées.**
- Modélisation en **schéma en étoile** (table de faits + dimensions) pour un vrai mini-entrepôt analytique.
- Reproduction de l'analyse en **Python / pandas** et construction d'un mini-pipeline **ETL**.

## Auteur

**Emmanuel MADOUKOU** — Diplômé en Mathématiques & Informatique, candidat en sciences des données.
GitHub : [github.com/willi04](https://github.com/willi04) · Plateforme : [goevent.africa](https://goevent.africa)
