SELECT * 
FROM tickets; 
# Fiche SQL GoEvent — Intermédiaire → Avancé
### 30 exercices en 8 modules + 2 mini-projets (Data Cleaning & EDA)

## MODULE 1 — JOINs avancés (3+ tables, self-join)
# *Consolide le piège de l'Ex 16 : bien choisir la colonne de jointure.*
-- 1.1** Pour chaque paiement **complété**, affiche le montant, le nom de l'acheteur et le titre de l'événement. 
SELECT full_name, amount, title
FROM goevent_db.payments t1
	JOIN goevent_db.tickets t2
		ON t1.ticket_id = t2.id
	JOIN goevent_db.events t3
		ON t2.event_id = t3.id
	JOIN goevent_db.users t4
		ON t4.id = t1.user_id
WHERE status = 'completed'
;

-- 1.2** Pour chaque événement, affiche son titre, sa catégorie et le **nom de son organisateur**.
SELECT title, category, full_name 
FROM goevent_db.events t1
	JOIN goevent_db.users t2
		ON t1.organizer_id = t2.id
;

-- 1.3** Affiche chaque utilisateur **parrainé** avec le nom de son **parrain**.
SELECT * 
FROM goevent_db.users t1
	JOIN goevent_db.users t2
		ON t1.referred_by_user_id = t2.id ; 

-- 1.4** Pour chaque ticket, affiche en une seule ligne : le nom de **l'acheteur**, le titre de l'événement, et le nom de **l'organisateur** de cet événement.
SELECT t2.title AS evenement, t3.full_name AS acheteur, t4.full_name AS organisateur
FROM goevent_db.tickets t1
	JOIN goevent_db.users t3
		ON t1.user_id= t3.id 
	JOIN goevent_db.events t2 
		ON t2.id = t1.event_id
	JOIN goevent_db.users t4
		ON t4.id = t2.organizer_id
;

## MODULE 2 — Anti-jointures & semi-jointures
-- Consolide le piège de l'Ex 18 : « ce qui existe d'un côté mais pas de l'autre ».
-- 2.1** Trouve les utilisateurs qui n'ont **jamais acheté de ticket**
SELECT full_name AS non_acheteur
FROM goevent_db.tickets t1
	LEFT JOIN goevent_db.users t3
		ON t1.user_id= t3.id
	LEFT JOIN goevent_db.payments t2
		ON t3.id = t2.user_id
WHERE amount IS NULL; 

-- 2.2** Trouve les événements qui n'ont **vendu aucun ticket**.
SELECT title AS EvenementNonVendu
FROM goevent_db.events t1
	LEFT JOIN goevent_db.tickets t3
		ON t3.event_id= t1.id
	LEFT JOIN goevent_db.payments t2
		ON t3.id = t2.ticket_id
WHERE status IS NULL;

-- 2.3** Trouve les utilisateurs qui ont **au moins un paiement complété**
SELECT full_name, ROW_NUMBER() OVER() AS rang
FROM users u 
WHERE EXISTS (SELECT *
						FROM payments p   
						WHERE u.id = p.user_id AND status = 'completed');

-- 2.4** Trouve les utilisateurs qui **n'ont jamais parrainé personne**.
SELECT full_name, ROW_NUMBER() OVER() AS rang
FROM users u 
WHERE NOT EXISTS (SELECT 1
						FROM users p   
						WHERE u.id = p.referred_by_user_id);
                        
## MODULE 3 — Sous-requêtes (scalaire, dérivée, corrélée)
-- 3.1** Affiche les paiements dont le montant dépasse la **moyenne générale** des paiements.
SELECT *
FROM payments
WHERE amount > (SELECT AVG(amount)
				FROM payments)
;

-- 3.2** À partir du total dépensé par chaque utilisateur, garde uniquement ceux qui ont dépensé **plus de 20 000** au total.
SELECT * 
FROM (SELECT 
    user_id, SUM(amount) AS total_depense
FROM payments
WHERE status = 'completed'
GROUP BY user_id) AS par_user
WHERE total_depense >= 20000
;

-- 3.3** Affiche les paiements dont le montant est supérieur à la **moyenne des paiements de ce même utilisateur**.
SELECT p.*
FROM payments p
WHERE p.amount > (
  SELECT AVG(p2.amount) FROM payments p2 WHERE p2.user_id = p.user_id
);

-- 3.4** Pour chaque catégorie d'événement, trouve **l'événement le plus cher**.
SELECT e.category, e.title, e.price
FROM events e
WHERE e.price = (
  SELECT MAX(e2.price) FROM events e2 WHERE e2.category = e.category
)
ORDER BY e.category;

## MODULE 4 — Agrégation avancée (GROUP BY multiple, pivot, %)
-- *Consolide le piège de l'Ex 22 : granularité du GROUP BY.*
-- 4.1** Par événement, calcule le **revenu total** (`SUM(amount)`), la **commission plateforme** (`SUM(platform_fee)`) 
-- et la **part organisateur** (`SUM(organizer_amount)`), sur les paiements complétés uniquement.
SELECT 
    e.id,
    e.title,
    SUM(p.amount) AS revenu,
    SUM(p.platform_fee) AS commission,
    SUM(p.organizer_amount) AS part_organisateur
FROM
    payments p
        JOIN
    tickets t ON t.id = p.ticket_id
        JOIN
    events e ON e.id = t.event_id
WHERE
    p.status = 'completed'
GROUP BY e.id , e.title
ORDER BY revenu DESC;

-- 4.2** Affiche uniquement les événements ayant généré **plus de 30 000** de revenu. *(HAVING)*
SELECT 
    e.title, SUM(p.amount) AS revenu
FROM
    payments p
        JOIN
    tickets t ON t.id = p.ticket_id
        JOIN
    events e ON e.id = t.event_id
WHERE
    p.status = 'completed'
GROUP BY e.id , e.title
HAVING SUM(p.amount) > 30000
ORDER BY revenu DESC;

-- 4.3** Par événement, compte le nombre de tickets payés **par orange money** vs **par cash** (deux colonnes)
SELECT 
    e.title,
    SUM(CASE
        WHEN payment_method = 'orange_money' THEN 1
        ELSE 0
    END) AS via_orange,
    SUM(CASE
        WHEN payment_method = 'cash' THEN 1
        ELSE 0
    END) AS via_cash
FROM
    tickets t
        JOIN
    events e ON t.event_id = e.id
GROUP BY e.title;

-- 4.4** Calcule la **part (%) de chaque catégorie** dans le revenu total. *(revenu de la catégorie ÷ revenu global × 100)*
SELECT 
    e.category,
    SUM(p.amount) AS revenu,
    ROUND(100.0 * SUM(p.amount) / (SELECT 
                    SUM(amount)
                FROM
                    payments
                WHERE
                    status = 'completed'),
            1) AS pourcentage
FROM
    payments p
        JOIN
    tickets t ON t.id = p.ticket_id
        JOIN
    events e ON e.id = t.event_id
WHERE
    p.status = 'completed'
GROUP BY e.category
ORDER BY revenu DESC;

## MODULE 5 — Fonctions fenêtre (RANK, top-N par groupe, LAG, cumul)
-- 5.1** Classe les événements par revenu décroissant, avec une colonne **rang** (1 = meilleur). *(RANK / DENSE_RANK)*
WITH classement AS ( 
	SELECT 
		e.title, SUM(p.amount) AS revenu, RANK() OVER (ORDER BY SUM(amount) DESC) AS rang
	FROM
		payments p
			JOIN
		tickets t ON t.id = p.ticket_id
			JOIN
		events e ON e.id = t.event_id 
	GROUP BY e.id, e.title 
)
SELECT title, revenu, rang, 
		CASE WHEN rang = 1 THEN 'meilleur' END AS mention
FROM classement 
ORDER BY revenu DESC; 

-- 5.2** Pour chaque utilisateur, garde **son plus gros paiement** uniquement. *(ROW_NUMBER PARTITION BY user_id + filtre = 1)*
SELECT *
FROM (
SELECT *, ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY amount DESC) AS rn
FROM payments ) t
WHERE rn = 1 ; 

-- 5.3** Trouve le **top 3 des acheteurs par événement** (par total dépensé sur cet événement). *(RANK PARTITION BY event_id — le grand classique)
WITH depenses AS (
  SELECT t.event_id, p.user_id, SUM(p.amount) AS total
  FROM payments p
  JOIN tickets t ON t.id = p.ticket_id
  WHERE p.status = 'completed'
  GROUP BY t.event_id, p.user_id
),
classement AS (
  SELECT d.*,
         RANK() OVER (PARTITION BY event_id ORDER BY total DESC) AS rang
  FROM depenses d
)
SELECT c.event_id, u.full_name, c.total, c.rang
FROM classement c
JOIN users u ON u.id = c.user_id
WHERE c.rang <= 3
ORDER BY c.event_id, c.rang;

-- 5.4** Calcule le **cumul du revenu dans le temps** (running total), ordonné par date d'achat. *(SUM(...) OVER (ORDER BY purchased_at))*
SELECT t.purchased_at, p.amount,
       SUM(p.amount) OVER (ORDER BY t.purchased_at) AS revenu_cumule
FROM payments p
JOIN tickets t ON t.id = p.ticket_id
WHERE p.status = 'completed'
ORDER BY t.purchased_at;

-- 5.5** Calcule le revenu **par mois**, puis la **variation** par rapport au mois précédent. *(LAG sur le CA mensuel)*
WITH par_mois AS (
  SELECT DATE_FORMAT(t.purchased_at, '%Y-%m-01') AS mois,  -- MySQL
         SUM(p.amount) AS ca
  FROM payments p
  JOIN tickets t ON t.id = p.ticket_id
  WHERE p.status = 'completed'
  GROUP BY DATE_FORMAT(t.purchased_at, '%Y-%m-01')
)
SELECT mois, ca,
       ca - LAG(ca) OVER (ORDER BY mois) AS variation
FROM par_mois
ORDER BY mois;

## MODULE 6 — CTE (WITH), y compris récursive
-- 6.1** Avec une CTE, calcule le total dépensé par utilisateur, puis affiche les 10 premiers avec leur **nom**.
WITH user_depense AS (
	SELECT 
		user_id, u.full_name, SUM(amount) AS total_depense
	FROM payments p
    JOIN users u ON p.user_id = u.id
	WHERE status = 'completed'
	GROUP BY user_id, u.full_name
)
SELECT *
FROM user_depense
ORDER BY total_depense DESC
LIMIT 10;

-- 6.2** Avec **deux CTE chaînées** : d'abord le revenu par événement, puis le revenu 
-- **par catégorie** à partir de la première.
WITH revenu_evt AS (
	SELECT 
    e.id,
    e.title,
    e.category,
    SUM(p.amount) AS revenu_evt
FROM
    payments p
        JOIN
    tickets t ON t.id = p.ticket_id
        JOIN
    events e ON e.id = t.event_id
WHERE
    p.status = 'completed'
GROUP BY e.id , e.title, e.category
), 
revenu_ctg AS (
	SELECT 
    category,
    SUM(revenu_evt) AS revenu_t_catg
FROM
    revenu_evt
GROUP BY category
)
SELECT category, revenu_t_catg
FROM revenu_ctg 
;

-- 6.3** Avec une **CTE récursive**, affiche toute la **chaîne de parrainage** issue de l'utilisateur d'`id` 30 
-- (ses filleuls, les filleuls de ses filleuls, …), avec le niveau de profondeur.
WITH RECURSIVE chaine_parrainage AS (
SELECT id, full_name, referred_by_user_id, 0 nv_profondeur
FROM users
WHERE id = 30

UNION ALL

SELECT 
u.id,
u.full_name,
u.referred_by_user_id, 
c.nv_profondeur + 1
FROM users u
INNER JOIN chaine_parrainage c ON u.referred_by_user_id = c.id
)
SELECT *
FROM chaine_parrainage
WHERE nv_profondeur > 0; 




# MINI-PROJET A — Data Cleaning (préparer une table propre)
-- But :** partir des données brutes (surtout `tickets` et `payments`) et produire une **table de faits propre et fiable**
-- pour l'analyse. Travaille sur des tables de staging, jamais sur l'original.
-- A1. Copies de travail
CREATE TABLE stg_tickets  AS SELECT * FROM tickets;
CREATE TABLE stg_payments AS SELECT * FROM payments;

-- A2. Booléens 't'/'f' -> 1/0 (si l'import PostgreSQL les a laissés en texte)
-- MySQL :
UPDATE stg_tickets SET is_used = (is_used = 't');

-- A3. Vides -> NULL (exemple sur quelques colonnes)
UPDATE stg_tickets 
SET 
    used_at = NULLIF(used_at, '')
WHERE
    used_at = '';
UPDATE stg_tickets 
SET 
    failure_reason = NULLIF(failure_reason, '')
WHERE
    failure_reason = '';
    
-- A4. Cohérence financière : base_price + platform_fee doit = amount
SELECT id, base_price, platform_fee, amount,
       (base_price + platform_fee) AS somme_attendue
FROM stg_payments
WHERE ABS((base_price + platform_fee) - amount) > 0.01;   -- lignes suspectes

-- A5. Orphelins
-- paiements dont le ticket n'existe pas
SELECT 
    p.id
FROM
    stg_payments p
        LEFT JOIN
    stg_tickets t ON t.id = p.ticket_id
WHERE
    t.id IS NULL;
-- tickets dont l'événement n'existe pas
SELECT 
    t.id
FROM
    stg_tickets t
        LEFT JOIN
    events e ON e.id = t.event_id
WHERE
    e.id IS NULL;

-- A6. Doublons de clés métier
SELECT 
    qr_hash, COUNT(*)
FROM
    stg_tickets
GROUP BY qr_hash
HAVING COUNT(*) > 1;
SELECT 
    transaction_id, COUNT(*)
FROM
    stg_payments
GROUP BY transaction_id
HAVING COUNT(*) > 1;

-- A7. Standardisation (exemple)
UPDATE stg_payments SET status = LOWER(TRIM(status));

-- A8. Table finale propre : une ligne par paiement complété
CREATE TABLE fait_ventes AS
SELECT p.id            AS id_paiement,
       p.user_id,
       t.event_id,
       p.amount        AS montant,
       t.payment_method AS canal,
       t.purchased_at  AS date_achat
FROM stg_payments p
JOIN stg_tickets t ON t.id = p.ticket_id
WHERE p.status = 'completed';

-- Contrôles qualité finaux (doivent tous renvoyer 0 / vide)
SELECT COUNT(*) FROM fait_ventes WHERE montant IS NULL OR montant <= 0;
SELECT COUNT(*) FROM fait_ventes WHERE date_achat IS NULL;
SELECT 
    id_paiement, COUNT(*)
FROM
    fait_ventes
GROUP BY id_paiement
HAVING COUNT(*) > 1;


/* =====================================================================
   MINI-PROJET B — EDA (solution de référence, avec insights à compléter)
   ===================================================================== */
   
   -- B1. Revenu par événement (top 10) + part du total
SELECT event_id, SUM(montant) AS revenu,
       ROUND(100.0 * SUM(montant) / (SELECT SUM(montant) FROM fait_ventes), 1) AS pct
FROM fait_ventes
GROUP BY event_id
ORDER BY revenu DESC
LIMIT 10;
-- Insight : Le revenu est extrêmement concentré : l'événement 8 génère à lui seul 87 % du chiffre d'affaires, et le top 2 en cumule 96 %. 
-- → L'activité dépend d'un unique événement → forte vulnérabilité : diversifier le portefeuille d'événements est un enjeu de survie.

-- B2. Taux de remplissage par événement
SELECT e.title, e.seats_sold, e.total_seats,
       ROUND(100.0 * e.seats_sold / NULLIF(e.total_seats, 0), 1) AS remplissage_pct
FROM events e
ORDER BY remplissage_pct DESC;
-- Insight : Le remplissage est quasi nul (maximum 2,5 %), et 5 des 7 événements n'ont vendu aucune place. → La plateforme est à un stade très précoce : des capacités importantes (jusqu'à 1000 sièges) sont affichées sans demande réelle encore.
--  → La priorité n'est pas la logistique mais l'acquisition (faire venir les premiers acheteurs).

-- B3. Taux d'échec de paiement (global)
SELECT status, COUNT(*) AS nb,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM payments), 1) AS pct
FROM payments
GROUP BY status;
-- Seuls 27 % des paiements aboutissent (completed), tandis que 51 % restent en attente (pending) et 22 % échouent. → Près des trois quarts des tentatives de paiement ne se concrétisent pas 
-- → il y a un problème majeur dans le tunnel de paiement. Hypothèses à investiguer : abandons, souci Orange Money, ou données de test.

-- B4. Canaux de paiement + panier moyen
SELECT canal, COUNT(*) AS nb, ROUND(AVG(montant), 0) AS panier_moyen
FROM fait_ventes
GROUP BY canal
ORDER BY nb DESC;
-- Insight : Orange Money domine en volume (7 paiements contre 3), mais le cash génère un panier moyen ~50× supérieur (7 333 contre 146). → Les petits montants passent par mobile, les gros par cash 
-- → deux usages très différents coexistent sur la plateforme.

-- B5. Effet du parrainage sur la dépense
SELECT 
    CASE
        WHEN u.referred_by_user_id IS NULL THEN 'Non parrainé'
        ELSE 'Parrainé'
    END AS type_user,
    ROUND(AVG(v.total), 0) AS depense_moyenne
FROM
    users u
        LEFT JOIN
    (SELECT 
        user_id, SUM(montant) AS total
    FROM
        fait_ventes
    GROUP BY user_id) v ON v.user_id = u.id
GROUP BY type_user;          -- on groupe par ce qu'on affiche
SELECT CASE WHEN u.referred_by_user_id IS NULL THEN 'Non parrainé' ELSE 'Parrainé' END AS type_user,
       COUNT(*)                              AS nb_users,
       COUNT(v.user_id)                      AS nb_acheteurs,
       ROUND(AVG(COALESCE(v.total, 0)), 0)   AS depense_moyenne_tous
FROM users u
LEFT JOIN (
  SELECT user_id, SUM(montant) AS total FROM fait_ventes GROUP BY user_id
) v ON v.user_id = u.id
GROUP BY type_user;

-- Insight : La comparaison parrainés / non-parrainés est impossible : 100 % des utilisateurs de la base sont parrainés (aucun groupe témoin). De plus, sur 29 parrainés, seuls 3 ont effectivement acheté. → L'effet du parrainage sur 
-- la dépense ne peut pas être mesuré à ce stade : il manque un groupe de comparaison, et l'échantillon d'acheteurs est trop faible pour conclure.

-- B6. Top organisateurs par revenu
SELECT 
    org.full_name AS organisateur, SUM(v.montant) AS revenu
FROM
    fait_ventes v
        JOIN
    events e ON e.id = v.event_id
        JOIN
    users org ON org.id = e.organizer_id
GROUP BY org.id , org.full_name
ORDER BY revenu DESC;
-- Insight : Un seul organisateur (« Demo Orga ») a généré du revenu — 20 000, soit la totalité du chiffre d'affaires. → Côté offre comme côté demande, 
-- l'activité repose sur un unique acteur → la plateforme n'a pas encore de base d'organisateurs actifs.

-- B7. Revenu par mois + variation
WITH par_mois AS (
  SELECT DATE_FORMAT(date_achat, '%Y-%m-01') AS mois, SUM(montant) AS ca
  FROM fait_ventes GROUP BY DATE_FORMAT(date_achat, '%Y-%m-01')
)
SELECT mois, ca, ca - LAG(ca) OVER (ORDER BY mois) AS variation
FROM par_mois ORDER BY mois;
-- Insight : Le revenu s'est effondré de 98 % après le premier mois (22 312 en mai → 312 en juin), puis est resté au plancher. → L'activité n'a pas de récurrence : le chiffre repose sur un pic unique, non reproduit ensuite. 
-- → Sans revenus réguliers, la plateforme n'a pas encore trouvé son rythme de croisière — l'enjeu est de transformer un coup unique en activité continue.

-- B8. Revenu et remplissage par catégorie
SELECT 
    e.category,
    SUM(v.montant) AS revenu,
    ROUND(AVG(100.0 * e.seats_sold / NULLIF(e.total_seats, 0)),
            1) AS remplissage_moyen_pct
FROM
    fait_ventes v
        JOIN
    events e ON e.id = v.event_id
GROUP BY e.category
ORDER BY revenu DESC;

-- Insight : Une seule catégorie (« Soirée ») a généré du revenu — 20 000, avec un remplissage de 2,5 %. → Toutes les autres catégories 
-- (concert, sport, conférence…) existent mais n'ont réalisé aucune vente → l'activité n'est pas seulement concentrée sur un événement, mais sur un seul type d'événement.