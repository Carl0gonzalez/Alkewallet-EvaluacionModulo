# AlkeWallet (MySQL 8) — Evaluación Módulo 3

Este repositorio contiene el diseño e implementación de una base de datos relacional para una billetera virtual (**AlkeWallet**), incluyendo creación del esquema, carga de datos de prueba, consultas SQL y operación transaccional con conversión de moneda. [file:389]

## Objetivo
Implementar una solución en MySQL 8 que permita:
- Administrar usuarios y su **moneda preferida**. [file:389]
- Registrar saldos por **(usuario, moneda)** para soportar multimoneda correctamente. [file:389]
- Ejecutar transferencias donde la **moneda destino siempre es la moneda preferida del receptor**, aplicando **tasa de cambio** cuando corresponda y registrando la tasa usada. [file:389]

## Concepto (resumen)
Una base de datos relacional organiza información en tablas relacionadas por claves primarias y foráneas, facilitando consistencia, consultas complejas (`JOIN`) e integridad referencial. [file:389]

## Comparativa breve (RDBMS)
| Tipo | Ejemplos | Licencia/costo | Fortalezas típicas | Consideraciones |
|---|---|---:|---|---|
| Libres | PostgreSQL, MySQL Community, MariaDB, SQLite | Gratis | Bajo costo, comunidad, flexibilidad | Soporte comercial opcional |
| Comerciales | Oracle DB, SQL Server (Enterprise), DB2 | Pago | Soporte enterprise, herramientas avanzadas | Costos de licencia/infra |
[file:389]

---

## Reglas funcionales implementadas
- Cada usuario tiene una **moneda preferida**. [file:389]
- La transferencia se origina en una moneda del emisor, pero la **moneda destino siempre es la moneda preferida del receptor**. [file:389]
- El saldo se gestiona por **(usuario, moneda)**. [file:389]
- Si la moneda de origen difiere de la destino, se usa una **tasa de cambio** y se registra la tasa utilizada en la transacción. [file:389]

---

## Diagrama entidad–relación (Mermaid)

```mermaid
erDiagram
  MONEDA {
    int currency_id PK
    string currency_name
    string currency_symbol UK
  }

  USUARIO {
    int user_id PK
    string nombre
    string correo_electronico UK
    string contrasena
    datetime created_at
    int currency_id FK
  }

  SALDO_USUARIO_MONEDA {
    int user_id PK,FK
    int currency_id PK,FK
    decimal saldo
  }

  TASA_CAMBIO {
    int rate_id PK
    int from_currency_id FK
    int to_currency_id FK
    decimal rate
    datetime updated_at
  }

  TRANSACCION {
    int transaction_id PK
    int sender_user_id FK
    int receiver_user_id FK
    int from_currency_id FK
    int to_currency_id FK
    decimal amount_from
    decimal rate_used
    decimal amount_to
    datetime transaction_date
  }

  MONEDA ||--o{ USUARIO : preferred
  USUARIO ||--o{ SALDO_USUARIO_MONEDA : tiene
  MONEDA ||--o{ SALDO_USUARIO_MONEDA : en

  MONEDA ||--o{ TASA_CAMBIO : from
  MONEDA ||--o{ TASA_CAMBIO : to

  USUARIO ||--o{ TRANSACCION : envia
  USUARIO ||--o{ TRANSACCION : recibe
  MONEDA ||--o{ TRANSACCION : moneda_origen
  MONEDA ||--o{ TRANSACCION : moneda_destino
```
[file:389]

---

## Contenido del repositorio
- `AlkeWallet.sql`: script completo con DDL, DML, función, trigger, procedimiento, consultas y vista top‑5. [file:389]
- Evidencias (capturas): se agregan según corresponda (creación BD, `DESCRIBE`, resultados de consultas, etc.).

---

## Ejecución rápida

### Requisitos
- MySQL 8.x (local o remoto).
- Cliente SQL (DBeaver, MySQL Shell, consola `mysql`, etc.).

### 1) Crear esquema y datos
Ejecuta el script `AlkeWallet.sql` en tu cliente SQL.

Comandos útiles para evidencias:
- `SHOW DATABASES;` para listar bases. [file:389]
- `SHOW TABLES;` para listar tablas del esquema activo. [file:389]
- `DESCRIBE <tabla>;` para ver estructura. [web:191]
- `SHOW CREATE TABLE <tabla>;` para ver el DDL final (útil para capturas). [web:245]

> Nota: si tu servidor tiene *binary logging* habilitado, la creación de funciones puede requerir habilitar `log_bin_trust_function_creators` como administrador. (Esto se detecta por error 1419).

### 2) Probar transferencias
El script incluye llamadas de ejemplo a `sp_transfer(...)` y consultas para verificar:
- Saldos actualizados.
- Registro en tabla `transaccion` con `rate_used` y `amount_to`. [file:389]

---

## Consultas incluidas (resumen)
- `SELECT` básico y filtros `WHERE`. [file:389]
- `JOIN` para obtener moneda preferida del usuario. [file:389]
- Listado completo de transacciones con datos de emisor/receptor y monedas. [file:389]
- Agregaciones (`COUNT`) y subconsulta para participación por usuario. [file:389]
- Vista `vw_top5_saldo_clp` para ranking top‑5 por saldo equivalente en CLP. [file:389]

---

## Resultados esperados
- El `JOIN` usuario–moneda devuelve la moneda preferida por usuario. [file:389]
- `sp_transfer` descuenta saldo al emisor en moneda origen, convierte con `tasa_cambio` y acredita al receptor en su moneda preferida. [file:389]
- `transaccion` registra `rate_used` y `amount_to` como auditoría de conversión. [file:389]
- La vista `vw_top5_saldo_clp` permite ranking unificado en CLP equivalente. [file:389]

---

## Autor
Carlo Javier González Rojas. [file:389]
