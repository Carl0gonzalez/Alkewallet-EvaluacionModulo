/* =========================================================
   AlkeWallet.sql  (MySQL 8 / InnoDB)
   - Multimoneda con conversión automática a moneda preferida
     del receptor (destino siempre = moneda del receptor)
   - Tasas de cambio
   - Transferencias ACID
   ========================================================= */

-- ---------------------------------------------------------
-- 0) Limpieza (opcional para re-ejecutar)
-- ---------------------------------------------------------
DROP DATABASE IF EXISTS AlkeWallet;

-- ---------------------------------------------------------
-- 1) Crear BD y usarla
-- ---------------------------------------------------------
CREATE DATABASE AlkeWallet;
USE AlkeWallet;

-- Verificación (para captura)
SHOW DATABASES;

-- ---------------------------------------------------------
-- 2) Tablas (DDL)
-- ---------------------------------------------------------

-- 2.1 Moneda
CREATE TABLE moneda (
    currency_id INT AUTO_INCREMENT PRIMARY KEY,
    currency_name VARCHAR(50) NOT NULL,
    currency_symbol VARCHAR(10) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- 2.2 Usuario
CREATE TABLE usuario (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    correo_electronico VARCHAR(150) NOT NULL UNIQUE,
    contrasena VARCHAR(255) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Moneda preferida del usuario (se usa como moneda destino al recibir)
    currency_id INT NOT NULL,

    CONSTRAINT fk_usuario_moneda
        FOREIGN KEY (currency_id) REFERENCES moneda(currency_id)
) ENGINE=InnoDB;

-- 2.3 Saldos por usuario/moneda (multimoneda real)
CREATE TABLE saldo_usuario_moneda (
    user_id INT NOT NULL,
    currency_id INT NOT NULL,
    saldo DECIMAL(15,2) NOT NULL DEFAULT 0.00,

    PRIMARY KEY (user_id, currency_id),

    CONSTRAINT fk_saldo_usuario
        FOREIGN KEY (user_id) REFERENCES usuario(user_id),
    CONSTRAINT fk_saldo_moneda
        FOREIGN KEY (currency_id) REFERENCES moneda(currency_id)
) ENGINE=InnoDB;

CREATE INDEX idx_saldo_currency ON saldo_usuario_moneda (currency_id);

-- 2.4 Tasas de cambio (from -> to)
CREATE TABLE tasa_cambio (
    rate_id INT AUTO_INCREMENT PRIMARY KEY,
    from_currency_id INT NOT NULL,
    to_currency_id INT NOT NULL,
    rate DECIMAL(18,8) NOT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_rate_from
        FOREIGN KEY (from_currency_id) REFERENCES moneda(currency_id),
    CONSTRAINT fk_rate_to
        FOREIGN KEY (to_currency_id) REFERENCES moneda(currency_id),

    CONSTRAINT uq_rate_pair UNIQUE (from_currency_id, to_currency_id)
) ENGINE=InnoDB;

CREATE INDEX idx_rate_pair ON tasa_cambio (from_currency_id, to_currency_id);

-- 2.5 Transacción
-- Regla: to_currency_id siempre será la moneda preferida del receptor.
CREATE TABLE transaccion (
    transaction_id INT AUTO_INCREMENT PRIMARY KEY,

    sender_user_id INT NOT NULL,
    receiver_user_id INT NOT NULL,

    from_currency_id INT NOT NULL,
    to_currency_id INT NOT NULL,

    amount_from DECIMAL(15,2) NOT NULL,
    rate_used DECIMAL(18,8) NOT NULL,
    amount_to DECIMAL(15,2) NOT NULL,

    transaction_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_trans_sender
        FOREIGN KEY (sender_user_id) REFERENCES usuario(user_id),
    CONSTRAINT fk_trans_receiver
        FOREIGN KEY (receiver_user_id) REFERENCES usuario(user_id),
    CONSTRAINT fk_trans_from_currency
        FOREIGN KEY (from_currency_id) REFERENCES moneda(currency_id),
    CONSTRAINT fk_trans_to_currency
        FOREIGN KEY (to_currency_id) REFERENCES moneda(currency_id)
) ENGINE=InnoDB;

-- Índices compuestos (optimización de búsquedas por usuario y fecha)
CREATE INDEX idx_trans_sender_date ON transaccion (sender_user_id, transaction_date);
CREATE INDEX idx_trans_receiver_date ON transaccion (receiver_user_id, transaction_date);
CREATE INDEX idx_trans_currency_date ON transaccion (from_currency_id, to_currency_id, transaction_date);

-- ---------------------------------------------------------
-- 3) Exploración para evidencias
-- ---------------------------------------------------------
SHOW TABLES;
DESCRIBE usuario;
DESCRIBE moneda;
DESCRIBE transaccion;

-- ---------------------------------------------------------
-- 4) Datos de prueba (DML)
-- ---------------------------------------------------------

-- 4.1 Monedas (CLP principal, se agregan USD/EUR)
INSERT INTO moneda (currency_name, currency_symbol) VALUES
('Peso Chileno', 'CLP'),
('Dólar Americano', 'USD'),
('Euro', 'EUR');

-- 4.2 Usuarios con moneda preferida distinta (para demostrar multimoneda)
INSERT INTO usuario (nombre, correo_electronico, contrasena, currency_id) VALUES
('Juan Pérez', 'juan.perez@example.com', 'passJuan123',
    (SELECT currency_id FROM moneda WHERE currency_symbol='CLP')),
('María López', 'maria.lopez@example.com', 'passMaria123',
    (SELECT currency_id FROM moneda WHERE currency_symbol='USD')),
('Carlos González', 'carlos.gonzalez@example.com', 'passCarlos123',
    (SELECT currency_id FROM moneda WHERE currency_symbol='EUR'));

-- 4.3 Saldos iniciales por moneda
INSERT INTO saldo_usuario_moneda (user_id, currency_id, saldo) VALUES
(1, (SELECT currency_id FROM moneda WHERE currency_symbol='CLP'), 100000.00),
(2, (SELECT currency_id FROM moneda WHERE currency_symbol='USD'), 200.00),
(3, (SELECT currency_id FROM moneda WHERE currency_symbol='EUR'), 150.00);

-- 4.4 Tasas de ejemplo (ajústalas a valores reales si quieres)
INSERT INTO tasa_cambio (from_currency_id, to_currency_id, rate) VALUES
((SELECT currency_id FROM moneda WHERE currency_symbol='USD'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='CLP'),
 950.00000000),
((SELECT currency_id FROM moneda WHERE currency_symbol='EUR'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='CLP'),
 1030.00000000),
((SELECT currency_id FROM moneda WHERE currency_symbol='CLP'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='USD'),
 1.0/950.00000000),
((SELECT currency_id FROM moneda WHERE currency_symbol='CLP'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='EUR'),
 1.0/1030.00000000),
((SELECT currency_id FROM moneda WHERE currency_symbol='CLP'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='CLP'),
 1.00000000),
((SELECT currency_id FROM moneda WHERE currency_symbol='USD'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='USD'),
 1.00000000),
((SELECT currency_id FROM moneda WHERE currency_symbol='EUR'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='EUR'),
 1.00000000);

-- ---------------------------------------------------------
-- 5) Función: obtener tasa de cambio (from -> to)
-- ---------------------------------------------------------
DELIMITER $$

CREATE FUNCTION fx_rate(p_from INT, p_to INT)
RETURNS DECIMAL(18,8)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_rate DECIMAL(18,8);

    SELECT rate INTO v_rate
    FROM tasa_cambio
    WHERE from_currency_id = p_from
      AND to_currency_id = p_to
    ORDER BY updated_at DESC
    LIMIT 1;

    RETURN v_rate;
END$$

DELIMITER ;

-- ---------------------------------------------------------
-- 6) Trigger: moneda destino = preferida receptor + cálculo de conversión
-- ---------------------------------------------------------
DELIMITER $$

CREATE TRIGGER bi_transaccion_enforce_calc
BEFORE INSERT ON transaccion
FOR EACH ROW
BEGIN
    DECLARE v_to_currency INT;
    DECLARE v_rate DECIMAL(18,8);

    -- Moneda destino forzada
    SELECT currency_id INTO v_to_currency
    FROM usuario
    WHERE user_id = NEW.receiver_user_id;

    IF v_to_currency IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Receptor no existe o no tiene moneda preferida';
    END IF;

    SET NEW.to_currency_id = v_to_currency;

    -- Conversión
    SET v_rate = fx_rate(NEW.from_currency_id, NEW.to_currency_id);

    IF v_rate IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No existe tasa de cambio hacia la moneda destino del receptor';
    END IF;

    SET NEW.rate_used = v_rate;
    SET NEW.amount_to = ROUND(NEW.amount_from * v_rate, 2);
END$$

DELIMITER ;

-- ---------------------------------------------------------
-- 7) Procedimiento: transferencia ACID (conversión automática)
-- ---------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_transfer(
    IN p_sender INT,
    IN p_receiver INT,
    IN p_from_currency INT,
    IN p_amount_from DECIMAL(15,2)
)
BEGIN
    DECLARE v_to_currency INT;
    DECLARE v_rate DECIMAL(18,8);
    DECLARE v_amount_to DECIMAL(15,2);
    DECLARE v_sender_balance DECIMAL(15,2);

    START TRANSACTION;

    -- Moneda destino = preferida del receptor
    SELECT currency_id INTO v_to_currency
    FROM usuario
    WHERE user_id = p_receiver
    FOR UPDATE;

    IF v_to_currency IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Receptor no existe o no tiene moneda preferida';
    END IF;

    -- Tasa from -> destino
    SET v_rate = fx_rate(p_from_currency, v_to_currency);
    IF v_rate IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No existe tasa de cambio para la conversión';
    END IF;

    SET v_amount_to = ROUND(p_amount_from * v_rate, 2);

    -- Saldo emisor (bloqueo)
    SELECT saldo INTO v_sender_balance
    FROM saldo_usuario_moneda
    WHERE user_id = p_sender AND currency_id = p_from_currency
    FOR UPDATE;

    IF v_sender_balance IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El emisor no tiene saldo en la moneda origen';
    END IF;

    IF v_sender_balance < p_amount_from THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Saldo insuficiente';
    END IF;

    -- Descontar al emisor
    UPDATE saldo_usuario_moneda
    SET saldo = saldo - p_amount_from
    WHERE user_id = p_sender AND currency_id = p_from_currency;

    -- Asegurar saldo receptor en moneda destino
    INSERT INTO saldo_usuario_moneda (user_id, currency_id, saldo)
    VALUES (p_receiver, v_to_currency, 0.00)
    ON DUPLICATE KEY UPDATE saldo = saldo;

    -- Acreditar al receptor
    UPDATE saldo_usuario_moneda
    SET saldo = saldo + v_amount_to
    WHERE user_id = p_receiver AND currency_id = v_to_currency;

    -- Registrar transacción (trigger valida y recalcula por consistencia)
    INSERT INTO transaccion
        (sender_user_id, receiver_user_id, from_currency_id, to_currency_id, amount_from, rate_used, amount_to)
    VALUES
        (p_sender, p_receiver, p_from_currency, v_to_currency, p_amount_from, 0, 0);

    COMMIT;
END$$

DELIMITER ;

-- ---------------------------------------------------------
-- 8) Transacciones de prueba
-- ---------------------------------------------------------

-- Juan (CLP) -> María (recibe USD)
CALL sp_transfer(
    1, 2,
    (SELECT currency_id FROM moneda WHERE currency_symbol='CLP'),
    15000.00
);

-- María (USD) -> Juan (recibe CLP)
CALL sp_transfer(
    2, 1,
    (SELECT currency_id FROM moneda WHERE currency_symbol='USD'),
    10.00
);

-- Carlos (EUR) -> María (recibe USD)
INSERT INTO tasa_cambio (from_currency_id, to_currency_id, rate) VALUES
((SELECT currency_id FROM moneda WHERE currency_symbol='EUR'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='USD'),
 1.08000000),
((SELECT currency_id FROM moneda WHERE currency_symbol='USD'),
 (SELECT currency_id FROM moneda WHERE currency_symbol='EUR'),
 1.0/1.08000000);

CALL sp_transfer(
    3, 2,
    (SELECT currency_id FROM moneda WHERE currency_symbol='EUR'),
    5.00
);

-- ---------------------------------------------------------
-- 9) Consultas (lectura, agregación, subconsulta, vista)
-- ---------------------------------------------------------

-- Consulta simple
SELECT user_id, nombre, correo_electronico, created_at
FROM usuario;

-- Filtros con WHERE
SELECT user_id, nombre
FROM usuario
WHERE nombre LIKE 'M%';

-- JOIN: moneda preferida de un usuario
SELECT u.user_id, u.nombre, m.currency_name, m.currency_symbol
FROM usuario u
JOIN moneda m ON u.currency_id = m.currency_id
WHERE u.user_id = 1;

-- Todas las transacciones (JOIN múltiple)
SELECT
    t.transaction_id,
    t.transaction_date,
    us.nombre AS sender_nombre,
    ur.nombre AS receiver_nombre,
    mf.currency_symbol AS from_currency,
    mt.currency_symbol AS to_currency,
    t.amount_from,
    t.rate_used,
    t.amount_to
FROM transaccion t
JOIN usuario us ON t.sender_user_id = us.user_id
JOIN usuario ur ON t.receiver_user_id = ur.user_id
JOIN moneda mf ON t.from_currency_id = mf.currency_id
JOIN moneda mt ON t.to_currency_id = mt.currency_id
ORDER BY t.transaction_date DESC;

-- Transacciones donde participa un usuario
SELECT
    t.transaction_id,
    t.transaction_date,
    us.nombre AS sender_nombre,
    ur.nombre AS receiver_nombre,
    mf.currency_symbol AS from_currency,
    mt.currency_symbol AS to_currency,
    t.amount_from,
    t.amount_to
FROM transaccion t
JOIN usuario us ON t.sender_user_id = us.user_id
JOIN usuario ur ON t.receiver_user_id = ur.user_id
JOIN moneda mf ON t.from_currency_id = mf.currency_id
JOIN moneda mt ON t.to_currency_id = mt.currency_id
WHERE t.sender_user_id = 1 OR t.receiver_user_id = 1
ORDER BY t.transaction_date DESC;

-- Agregación (COUNT)
SELECT sender_user_id, COUNT(*) AS total_enviadas
FROM transaccion
GROUP BY sender_user_id;

-- Subconsulta: total de participaciones
SELECT u.user_id, u.nombre,
       (SELECT COUNT(*)
        FROM transaccion t
        WHERE t.sender_user_id = u.user_id OR t.receiver_user_id = u.user_id) AS total_participaciones
FROM usuario u;

-- UPDATE: cambiar correo
UPDATE usuario
SET correo_electronico = 'nuevo.correo@example.com'
WHERE user_id = 1;

-- DELETE: eliminar transacción
DELETE FROM transaccion
WHERE transaction_id = 1;

-- Vista (top‑5) por saldo equivalente CLP
CREATE OR REPLACE VIEW vw_top5_saldo_clp AS
SELECT
    u.user_id,
    u.nombre,
    ROUND(SUM(
        CASE
            WHEN m.currency_symbol = 'CLP' THEN s.saldo
            ELSE s.saldo * fx_rate(s.currency_id, (SELECT currency_id FROM moneda WHERE currency_symbol='CLP'))
        END
    ), 2) AS saldo_total_clp
FROM usuario u
JOIN saldo_usuario_moneda s ON s.user_id = u.user_id
JOIN moneda m ON m.currency_id = s.currency_id
GROUP BY u.user_id, u.nombre
ORDER BY saldo_total_clp DESC
LIMIT 5;

SELECT * FROM vw_top5_saldo_clp;

-- Evidencias finales
SHOW TABLES;
DESCRIBE saldo_usuario_moneda;
DESCRIBE tasa_cambio;
DESCRIBE transaccion;

SHOW CREATE TABLE usuario;
SHOW CREATE TABLE transaccion;
```
