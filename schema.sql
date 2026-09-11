-- =====================================================================
--  GoEvent Analytics — Schéma de la base (MySQL)
--  Recrée les 4 tables, puis charge les CSV du dossier data/ pour
--  reproduire le projet. Les données sont anonymisées.
--  Ordre de création : users -> events -> tickets -> payments
--  (une table qui en référence une autre est créée après elle).
-- =====================================================================

CREATE DATABASE IF NOT EXISTS goevent_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE goevent_db;

-- Suppression dans l'ordre inverse des dépendances (si ré-exécution)
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS tickets;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS users;

-- ---------------------------------------------------------------------
-- users : comptes de la plateforme (fans, organisateurs, staff)
--         referred_by_user_id -> users.id (parrainage : auto-référence)
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id                  INT PRIMARY KEY,
    full_name           VARCHAR(255),
    email               VARCHAR(255),
    phone_number        VARCHAR(50),
    role                VARCHAR(50),        -- fan / organizer / agent / staff / admin
    org_name            VARCHAR(255),
    is_active           TINYINT(1),
    created_at          DATETIME,
    orange_money        VARCHAR(50),
    referred_by_user_id INT,
    commission_rate     DECIMAL(5,2),
    staff_function      VARCHAR(100),
    CONSTRAINT fk_users_parrain
        FOREIGN KEY (referred_by_user_id) REFERENCES users(id)
);

-- ---------------------------------------------------------------------
-- events : événements  (organizer_id -> users.id)
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
    organizer_id INT,
    CONSTRAINT fk_events_organizer
        FOREIGN KEY (organizer_id) REFERENCES users(id)
);

-- ---------------------------------------------------------------------
-- tickets : billets  (user_id -> users.id, event_id -> events.id)
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
    CONSTRAINT fk_tickets_user  FOREIGN KEY (user_id)  REFERENCES users(id),
    CONSTRAINT fk_tickets_event FOREIGN KEY (event_id) REFERENCES events(id)
);

-- ---------------------------------------------------------------------
-- payments : paiements  (user_id -> users.id, ticket_id -> tickets.id)
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    id               INT PRIMARY KEY,
    user_id          INT,
    ticket_id        INT,
    amount           DECIMAL(12,2),
    base_price       DECIMAL(12,2),
    platform_fee     DECIMAL(12,2),
    organizer_amount DECIMAL(12,2),
    status           VARCHAR(50),   -- completed / failed / pending
    transaction_id   VARCHAR(255),
    CONSTRAINT fk_payments_user   FOREIGN KEY (user_id)   REFERENCES users(id),
    CONSTRAINT fk_payments_ticket FOREIGN KEY (ticket_id) REFERENCES tickets(id)
);

-- =====================================================================
--  Chargement des données (adapter le chemin des CSV du dossier data/)
--  Décommente si tu utilises LOAD DATA. Sinon, importe les CSV via
--  l'assistant "Table Data Import Wizard" de MySQL Workbench.
--  Charger dans l'ordre : users -> events -> tickets -> payments.
-- =====================================================================
-- LOAD DATA LOCAL INFILE 'data/users.csv'    INTO TABLE users
--   FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;
-- LOAD DATA LOCAL INFILE 'data/events.csv'   INTO TABLE events    ... ;
-- LOAD DATA LOCAL INFILE 'data/tickets.csv'  INTO TABLE tickets   ... ;
-- LOAD DATA LOCAL INFILE 'data/payments.csv' INTO TABLE payments  ... ;
