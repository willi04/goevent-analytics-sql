-- =====================================================================
--  GoEvent Analytics — Nettoyage, contrôle qualité et analyse (MySQL 8)
--  Auteur : Emmanuel MADOUKOU
--
--  Prérequis : exécuter schema.sql (création des tables + chargement).
--  Données : export anonymisé de la phase de test de GoEvent
--  (29 utilisateurs, 7 événements, 44 billets, 37 paiements),
--  dont une partie de données de démonstration.
--
--  Plan
--    1. Tables de staging et standardisation
--    2. Contrôles qualité
--    3. Table de faits fait_ventes et contrôles finaux
--    4. Analyses exploratoires (EDA)
--    5. Annexe : requêtes d'exploration (jointures, sous-requêtes,
--       fonctions fenêtre, CTE)
-- =====================================================================

USE goevent_db;


-- =====================================================================
-- 1. TABLES DE STAGING ET STANDARDISATION
--    On travaille sur des copies pour ne jamais modifier les sources.
-- =====================================================================

DROP TABLE IF EXISTS stg_tickets;
DROP TABLE IF EXISTS stg_payments;
CREATE TABLE stg_tickets  AS SELECT * FROM tickets;
CREATE TABLE stg_payments AS SELECT * FROM payments;

-- Valeurs textuelles harmonisées (casse, espaces)
UPDATE stg_payments SET status         = LOWER(TRIM(status));
UPDATE stg_tickets  SET payment_status = LOWER(TRIM(payment_status)),
                        payment_method = LOWER(TRIM(payment_method));


-- =====================================================================
-- 2. CONTRÔLES QUALITÉ
-- =====================================================================

-- 2.1 Intégrité référentielle : paiements sans billet
--     Résultat : 0
SELECT p.id
FROM stg_payments p
LEFT JOIN stg_tickets t ON t.id = p.ticket_id
WHERE t.id IS NULL;

-- 2.2 Intégrité référentielle : billets dont l'événement est absent
--     Résultat : 31 billets sur 44, répartis sur 12 événements absents de
--     l'export. Conséquence : toute analyse qui joint billets et événements
--     ne porte que sur une partie des ventes (voir 4.6 et 4.8).
SELECT t.event_id, COUNT(*) AS nb_billets
FROM stg_tickets t
LEFT JOIN events e ON e.id = t.event_id
WHERE e.id IS NULL
GROUP BY t.event_id
ORDER BY nb_billets DESC;

-- 2.3 Doublons de clés métier (QR code, identifiant de transaction)
--     Résultat : aucun doublon
SELECT qr_hash, COUNT(*) AS nb
FROM stg_tickets
GROUP BY qr_hash
HAVING COUNT(*) > 1;

SELECT transaction_id, COUNT(*) AS nb
FROM stg_payments
GROUP BY transaction_id
HAVING COUNT(*) > 1;

-- 2.4 Cohérence financière
--     Première hypothèse testée : base_price + platform_fee = amount.
--     Elle échoue sur 34 paiements sur 37 : ce n'est pas la règle métier.
SELECT COUNT(*) AS nb_ecarts_hypothese_1
FROM stg_payments
WHERE ABS(base_price + platform_fee - amount) > 0.01;

--     Règle réelle : amount = organizer_amount + platform_fee.
--     Résultat : 0 écart sur 37 paiements.
SELECT COUNT(*) AS nb_ecarts_regle_reelle
FROM stg_payments
WHERE ABS(organizer_amount + platform_fee - amount) > 0.01;

--     Structure des frais déduite des ratios : l'acheteur paie le prix
--     + 4 %, l'organisateur reçoit 93 % du prix, la plateforme garde 11 %.
--     Les paiements cash (3) sont sans commission.
SELECT ROUND(amount / base_price, 3)           AS ratio_paye,
       ROUND(organizer_amount / base_price, 3) AS ratio_organisateur,
       ROUND(platform_fee / base_price, 3)     AS ratio_plateforme,
       COUNT(*)                                AS nb_paiements
FROM stg_payments
WHERE base_price > 0
GROUP BY ratio_paye, ratio_organisateur, ratio_plateforme;

-- 2.5 Cohérence entre statut du billet et statut du paiement
--     Résultat : cohérent. 3 billets gratuits et 4 réservations cash
--     n'ont pas de paiement, ce qui est normal.
SELECT t.payment_status, p.status, t.payment_method, COUNT(*) AS nb
FROM stg_tickets t
LEFT JOIN stg_payments p ON p.ticket_id = t.id
GROUP BY t.payment_status, p.status, t.payment_method
ORDER BY t.payment_status, p.status;

-- 2.6 Parrainage : part des utilisateurs ayant un parrain
--     Résultat : 0 sur 29. La colonne est vide dans l'export. Chargée sans
--     NULLIF, la chaîne vide deviendrait 0 et ferait croire à tort que
--     100 % des utilisateurs sont parrainés.
SELECT COUNT(*)                   AS nb_users,
       COUNT(referred_by_user_id) AS nb_parraines
FROM users;


-- =====================================================================
-- 3. TABLE DE FAITS fait_ventes : une ligne par paiement complété
-- =====================================================================

DROP TABLE IF EXISTS fait_ventes;
CREATE TABLE fait_ventes AS
SELECT p.id               AS id_paiement,
       p.user_id,
       t.event_id,
       p.amount           AS montant,
       p.platform_fee     AS commission,
       p.organizer_amount AS part_organisateur,
       t.payment_method   AS canal,
       t.purchased_at     AS date_achat
FROM stg_payments p
JOIN stg_tickets  t ON t.id = p.ticket_id
WHERE p.status = 'completed';

-- Contrôles finaux : chaque requête doit renvoyer 0 ou aucune ligne
SELECT COUNT(*) AS montants_invalides FROM fait_ventes WHERE montant IS NULL OR montant <= 0;
SELECT COUNT(*) AS dates_manquantes   FROM fait_ventes WHERE date_achat IS NULL;
SELECT id_paiement, COUNT(*) AS nb
FROM fait_ventes
GROUP BY id_paiement
HAVING COUNT(*) > 1;

-- Volume : 10 paiements complétés, 23 022,32 FCFA au total
SELECT COUNT(*) AS nb_ventes, SUM(montant) AS ca_total FROM fait_ventes;


-- =====================================================================
-- 4. ANALYSES EXPLORATOIRES
--    Volumes très faibles et données en partie de démonstration :
--    les lectures ci-dessous décrivent l'échantillon, elles ne sont pas
--    des conclusions statistiques.
-- =====================================================================

-- 4.1 Concentration du revenu par événement
SELECT event_id,
       SUM(montant) AS revenu,
       ROUND(100.0 * SUM(montant) / (SELECT SUM(montant) FROM fait_ventes), 1) AS pct_du_total
FROM fait_ventes
GROUP BY event_id
ORDER BY revenu DESC;
-- Lecture : l'événement 8 représente 87 % du revenu, les deux premiers 96 %.

-- 4.2 Taux de remplissage (sur les 7 événements présents dans l'export)
SELECT e.title, e.seats_sold, e.total_seats,
       ROUND(100.0 * e.seats_sold / NULLIF(e.total_seats, 0), 1) AS remplissage_pct
FROM events e
ORDER BY remplissage_pct DESC;
-- Lecture : maximum 2,5 % ; 5 événements sur 7 n'ont vendu aucune place.

-- 4.3 Issue des paiements
SELECT status,
       COUNT(*) AS nb,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM stg_payments), 1) AS pct
FROM stg_payments
GROUP BY status
ORDER BY nb DESC;
-- Lecture : 27 % complétés, 51 % en attente, 22 % échoués.

-- Qui a produit les paiements non aboutis ?
SELECT user_id, status, COUNT(*) AS nb
FROM stg_payments
WHERE status <> 'completed'
GROUP BY user_id, status
ORDER BY nb DESC;
-- Lecture : les 19 paiements en attente viennent tous du même compte, qui
-- totalise 23 des 27 paiements non aboutis. Ce sont des essais répétés dans
-- l'environnement de test de l'agrégateur Orange Money : ils mesurent ce
-- test, pas le comportement des acheteurs.

-- 4.4 Canaux de paiement et panier moyen
SELECT canal, COUNT(*) AS nb, ROUND(AVG(montant), 0) AS panier_moyen
FROM fait_ventes
GROUP BY canal
ORDER BY nb DESC;
-- Lecture : 7 paiements Orange Money (panier moyen 146), 3 paiements cash
-- (panier moyen 7 333) : les petits montants passent par le mobile.

-- 4.5 Effet du parrainage sur la dépense
SELECT CASE WHEN u.referred_by_user_id IS NULL THEN 'Non parrainé' ELSE 'Parrainé' END AS type_user,
       COUNT(*)                            AS nb_users,
       COUNT(v.user_id)                    AS nb_acheteurs,
       ROUND(AVG(COALESCE(v.total, 0)), 0) AS depense_moyenne
FROM users u
LEFT JOIN (SELECT user_id, SUM(montant) AS total FROM fait_ventes GROUP BY user_id) v
       ON v.user_id = u.id
GROUP BY type_user;
-- Lecture : aucun utilisateur n'a de parrain dans l'export (voir 2.6) ;
-- l'effet du parrainage n'est donc pas mesurable.

-- 4.6 Revenu par organisateur
SELECT org.id, org.org_name AS organisation, SUM(v.montant) AS revenu
FROM fait_ventes v
JOIN events e   ON e.id   = v.event_id
JOIN users  org ON org.id = e.organizer_id
GROUP BY org.id, org.org_name
ORDER BY revenu DESC;
-- Lecture : seuls 20 000 FCFA sur 23 022 sont rattachables à un organisateur,
-- tous à « Demo Organisation ». Les 3 022 restants portent sur des événements
-- absents de l'export (voir 2.2). Le revenu principal provient donc d'un
-- événement de démonstration.

-- 4.7 Revenu mensuel et variation
WITH par_mois AS (
    SELECT DATE_FORMAT(date_achat, '%Y-%m') AS mois, SUM(montant) AS ca
    FROM fait_ventes
    GROUP BY DATE_FORMAT(date_achat, '%Y-%m')
)
SELECT mois, ca, ca - LAG(ca) OVER (ORDER BY mois) AS variation
FROM par_mois
ORDER BY mois;
-- Lecture : 22 312 en mai, 312 en juin, 398 en juillet. Le pic de mai
-- correspond à l'événement de démonstration de 4.6.

-- 4.8 Revenu par catégorie (événements présents dans l'export)
SELECT e.category, SUM(v.montant) AS revenu
FROM fait_ventes v
JOIN events e ON e.id = v.event_id
GROUP BY e.category
ORDER BY revenu DESC;
-- Lecture : seule la catégorie « Soirée » apparaît, mais 13 % du revenu porte
-- sur des événements absents de l'export : ce résultat n'est pas généralisable.


-- =====================================================================
-- 5. ANNEXE : REQUÊTES D'EXPLORATION
-- =====================================================================

-- 5.1 Jointures sur 4 tables : acheteur, montant et événement des paiements complétés
SELECT u.full_name AS acheteur, p.amount, e.title AS evenement
FROM payments p
JOIN tickets t ON t.id = p.ticket_id
JOIN events  e ON e.id = t.event_id
JOIN users   u ON u.id = p.user_id
WHERE p.status = 'completed';

-- 5.2 Auto-jointure : billet, acheteur et organisateur de l'événement
SELECT e.title AS evenement, a.full_name AS acheteur, o.full_name AS organisateur
FROM tickets t
JOIN users  a ON a.id = t.user_id
JOIN events e ON e.id = t.event_id
JOIN users  o ON o.id = e.organizer_id;

-- 5.3 Anti-jointure : utilisateurs sans aucun paiement complété
SELECT u.full_name AS non_acheteur
FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM payments p
    WHERE p.user_id = u.id AND p.status = 'completed'
);

-- 5.4 Anti-jointure : événements sans aucun billet payé
SELECT e.title AS evenement_sans_vente
FROM events e
WHERE NOT EXISTS (
    SELECT 1
    FROM tickets t
    JOIN payments p ON p.ticket_id = t.id
    WHERE t.event_id = e.id AND p.status = 'completed'
);

-- 5.5 Sous-requête corrélée : paiements supérieurs à la moyenne du même utilisateur
SELECT p.*
FROM payments p
WHERE p.amount > (SELECT AVG(p2.amount) FROM payments p2 WHERE p2.user_id = p.user_id);

-- 5.6 Sous-requête corrélée : événement le plus cher de chaque catégorie
SELECT e.category, e.title, e.price
FROM events e
WHERE e.price = (SELECT MAX(e2.price) FROM events e2 WHERE e2.category = e.category)
ORDER BY e.category;

-- 5.7 Pivot : billets par canal de paiement et par événement
SELECT t.event_id,
       SUM(CASE WHEN t.payment_method = 'orange_money' THEN 1 ELSE 0 END) AS via_orange_money,
       SUM(CASE WHEN t.payment_method = 'cash'         THEN 1 ELSE 0 END) AS via_cash,
       SUM(CASE WHEN t.payment_method = 'gratuit'      THEN 1 ELSE 0 END) AS gratuits
FROM tickets t
GROUP BY t.event_id
ORDER BY t.event_id;

-- 5.8 Fonction fenêtre : classement des événements par revenu
SELECT event_id, SUM(montant) AS revenu,
       RANK() OVER (ORDER BY SUM(montant) DESC) AS rang
FROM fait_ventes
GROUP BY event_id;

-- 5.9 Fonction fenêtre : plus gros paiement de chaque utilisateur
SELECT *
FROM (
    SELECT p.*, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY amount DESC) AS rn
    FROM payments p
) classes
WHERE rn = 1;

-- 5.10 Fonction fenêtre : top 3 des acheteurs par événement
WITH depenses AS (
    SELECT event_id, user_id, SUM(montant) AS total
    FROM fait_ventes
    GROUP BY event_id, user_id
),
classement AS (
    SELECT d.*, RANK() OVER (PARTITION BY event_id ORDER BY total DESC) AS rang
    FROM depenses d
)
SELECT c.event_id, u.full_name, c.total, c.rang
FROM classement c
JOIN users u ON u.id = c.user_id
WHERE c.rang <= 3
ORDER BY c.event_id, c.rang;

-- 5.11 Fonction fenêtre : revenu cumulé dans le temps
SELECT date_achat, montant,
       SUM(montant) OVER (ORDER BY date_achat) AS revenu_cumule
FROM fait_ventes
ORDER BY date_achat;

-- 5.12 CTE chaînées : revenu par événement, puis par catégorie
WITH revenu_evenement AS (
    SELECT v.event_id, e.category, SUM(v.montant) AS revenu
    FROM fait_ventes v
    JOIN events e ON e.id = v.event_id
    GROUP BY v.event_id, e.category
),
revenu_categorie AS (
    SELECT category, SUM(revenu) AS revenu
    FROM revenu_evenement
    GROUP BY category
)
SELECT * FROM revenu_categorie ORDER BY revenu DESC;

-- 5.13 CTE récursive : chaîne de parrainage à partir d'un utilisateur
--      Renvoie 0 ligne sur l'export public (aucun parrainage, voir 2.6) ;
--      la requête reste valable sur la base complète.
WITH RECURSIVE chaine_parrainage AS (
    SELECT id, full_name, referred_by_user_id, 0 AS profondeur
    FROM users
    WHERE id = 30
    UNION ALL
    SELECT u.id, u.full_name, u.referred_by_user_id, c.profondeur + 1
    FROM users u
    JOIN chaine_parrainage c ON u.referred_by_user_id = c.id
)
SELECT * FROM chaine_parrainage WHERE profondeur > 0;
