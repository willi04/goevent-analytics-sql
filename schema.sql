-- =====================================================================
--  GoEvent Analytics — Schéma et chargement des données (MySQL 8)
--
--  Recrée les 4 tables puis charge les CSV anonymisés du dossier
--  data_public/. Les conversions de type indispensables (texte vide
--  -> NULL, booléens 't'/'f' -> 1/0) sont faites AU CHARGEMENT : MySQL
--  en mode strict refuse une chaîne vide dans une colonne DATETIME ou INT.
--
--  Ordre : users -> events -> tickets -> payments
--  (une table qui en référence une autre est créée et chargée après elle).
-- =====================================================================

CREATE DATABASE IF NOT EXISTS goevent_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE goevent_db;

DROP TABLE IF EXISTS fait_ventes;
DROP TABLE IF EXISTS stg_payments;
DROP TABLE IF EXISTS stg_tickets;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS tickets;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS users;

-- ---------------------------------------------------------------------
-- users : comptes (fans, organisateurs, agents, staff, admin)
--         referred_by_user_id -> users.id (parrainage, auto-référence)
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id                  INT PRIMARY KEY,
    full_name           VARCHAR(255),
    email               VARCHAR(255),
    phone_number        VARCHAR(50),
    orange_money        VARCHAR(50),
    role                VARCHAR(50),        -- fan / organizer / agent / staff / admin
    org_name            VARCHAR(255),
    is_active           TINYINT(1),
    created_at          DATETIME,
    referred_by_user_id INT,
    commission_rate     DECIMAL(5,2),
    staff_function      VARCHAR(100),
    CONSTRAINT fk_users_parrain
        FOREIGN KEY (referred_by_user_id) REFERENCES users(id)
);

-- ---------------------------------------------------------------------
-- events : événements (organizer_id -> users.id)
-- ---------------------------------------------------------------------
CREATE TABLE events (
    id           INT PRIMARY KEY,
    title        VARCHAR(255),
    location     VARCHAR(255),
    category     VARCHAR(100),
    event_date   DATETIME,
    price        DECIMAL(12,2),
    total_seats  INT,
    seats_sold   INT,
    is_active    TINYINT(1),
    created_at   DATETIME,
    organizer_id INT,
    CONSTRAINT fk_events_organizer
        FOREIGN KEY (organizer_id) REFERENCES users(id)
);

-- ---------------------------------------------------------------------
-- tickets : billets (user_id -> users.id ; event_id -> events.id)
-- Pas de clé étrangère sur event_id : l'export public ne contient que
-- 7 événements, alors que les billets en référencent 15. Ces billets
-- orphelins sont détectés et documentés dans goevent_analytics.sql
-- au lieu d'être rejetés au chargement.
-- ---------------------------------------------------------------------
CREATE TABLE tickets (
    id             INT PRIMARY KEY,
    qr_hash        VARCHAR(255),
    payment_status VARCHAR(50),   -- paye / paye_cash / echec_paiement / en_attente_om / reservation_cash
    payment_ref    VARCHAR(255),
    is_used        TINYINT(1),
    used_at        DATETIME,
    purchased_at   DATETIME,
    user_id        INT,
    event_id       INT,
    payment_method VARCHAR(50),   -- orange_money / cash / gratuit
    cash_amount    DECIMAL(12,2),
    failure_reason VARCHAR(255),
    CONSTRAINT fk_tickets_user FOREIGN KEY (user_id) REFERENCES users(id)
);

-- ---------------------------------------------------------------------
-- payments : paiements (user_id -> users.id ; ticket_id -> tickets.id)
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    id               INT PRIMARY KEY,
    user_id          INT,
    ticket_id        INT,
    amount           DECIMAL(12,2),  -- payé par l'acheteur
    base_price       DECIMAL(12,2),  -- prix affiché du billet
    platform_fee     DECIMAL(12,2),  -- commission totale de la plateforme
    organizer_amount DECIMAL(12,2),  -- reversé à l'organisateur
    status           VARCHAR(50),    -- completed / failed / pending
    transaction_id   VARCHAR(255),
    CONSTRAINT fk_payments_user   FOREIGN KEY (user_id)   REFERENCES users(id),
    CONSTRAINT fk_payments_ticket FOREIGN KEY (ticket_id) REFERENCES tickets(id)
);

-- =====================================================================
--  Chargement des CSV (séparateur ';', fins de ligne Windows)
--  Prérequis : local_infile activé côté serveur et client
--    (SET GLOBAL local_infile = 1; et option --local-infile=1).
--  Lancer depuis la racine du dépôt pour que les chemins relatifs marchent.
--  Variante sans LOAD DATA : assistant d'import de MySQL Workbench,
--  en appliquant les mêmes conversions ensuite.
-- =====================================================================

LOAD DATA LOCAL INFILE 'data_public/users_public.csv'
INTO TABLE users
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, full_name, email, @phone, @om, role, @org, @active, @created, @ref, @comm, @staff)
SET phone_number        = NULLIF(@phone, ''),
    orange_money        = NULLIF(@om, ''),
    org_name            = NULLIF(@org, ''),
    is_active           = (@active = 't'),
    created_at          = NULLIF(@created, ''),
    referred_by_user_id = NULLIF(@ref, ''),   -- sans NULLIF, '' deviendrait 0
    commission_rate     = NULLIF(@comm, ''),
    staff_function      = NULLIF(@staff, '');

LOAD DATA LOCAL INFILE 'data_public/events_public.csv'
INTO TABLE events
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, title, @description, location, category, event_date, price,
 total_seats, seats_sold, @cover_image_url, @ticket_tiers, @active, @created, organizer_id)
SET is_active  = (@active = 't'),
    created_at = NULLIF(@created, '');

LOAD DATA LOCAL INFILE 'data_public/tickets_public.csv'
INTO TABLE tickets
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, qr_hash, payment_status, payment_ref, @used, @used_at, purchased_at,
 user_id, event_id, payment_method, @cash, @failure)
SET is_used        = (@used = 't'),
    used_at        = NULLIF(@used_at, ''),
    cash_amount    = NULLIF(@cash, ''),
    failure_reason = NULLIF(@failure, '');

LOAD DATA LOCAL INFILE 'data_public/payments_public.csv'
INTO TABLE payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(id, user_id, ticket_id, amount, base_price, platform_fee, organizer_amount, status, transaction_id);

-- Vérification du chargement : 29 / 7 / 44 / 37 lignes attendues
SELECT 'users' AS table_name, COUNT(*) AS nb_lignes FROM users
UNION ALL SELECT 'events',   COUNT(*) FROM events
UNION ALL SELECT 'tickets',  COUNT(*) FROM tickets
UNION ALL SELECT 'payments', COUNT(*) FROM payments;
