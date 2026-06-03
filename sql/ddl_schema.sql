-- ============================================================
--  0. BASE DE DATOS
-- ============================================================
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'FinPulseDWH')
    CREATE DATABASE FinPulseDWH;
GO

USE FinPulseDWH;
GO

-- ============================================================
--  1. ESQUEMAS
-- ============================================================
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dim')
    EXEC('CREATE SCHEMA dim');
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'fact')
    EXEC('CREATE SCHEMA fact');
GO

-- ============================================================
--  2. DIMENSIONES
-- ============================================================

-- ------------------------------------------------------------
--  dim.tiempo
--  Granularidad: 1 fila por día calendario
--  Rango sugerido: 2021-01-01 → 2025-12-31
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim.tiempo;
CREATE TABLE dim.tiempo (
    tiempo_sk           INT             NOT NULL,   -- Surrogate key (formato YYYYMMDD)
    fecha               DATE            NOT NULL,
    anio                SMALLINT        NOT NULL,
    trimestre           TINYINT         NOT NULL,   -- 1 a 4
    mes                 TINYINT         NOT NULL,   -- 1 a 12
    nombre_mes          VARCHAR(20)     NOT NULL,   -- 'Enero', 'Febrero', ...
    semana_anio         TINYINT         NOT NULL,   -- ISO week
    dia_mes             TINYINT         NOT NULL,
    dia_semana          TINYINT         NOT NULL,   -- 1 = Lunes, 7 = Domingo
    nombre_dia          VARCHAR(20)     NOT NULL,
    es_fin_semana       BIT             NOT NULL DEFAULT 0,
    es_feriado_peru     BIT             NOT NULL DEFAULT 0,
    nombre_feriado      VARCHAR(60)     NULL,
    es_quincena         BIT             NOT NULL DEFAULT 0,   -- Día 15 o último del mes
    es_fin_mes          BIT             NOT NULL DEFAULT 0,
    CONSTRAINT PK_dim_tiempo PRIMARY KEY (tiempo_sk)
);
GO

-- ------------------------------------------------------------
--  dim.cliente
--  SCD Tipo 2: historial de cambios en segmento y nivel de riesgo
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim.cliente;
CREATE TABLE dim.cliente (
    cliente_sk              INT             NOT NULL IDENTITY(1,1),
    cliente_id              VARCHAR(20)     NOT NULL,
    nombre                  VARCHAR(100)    NOT NULL,
    apellido                VARCHAR(100)    NOT NULL,
    tipo_documento          VARCHAR(10)     NOT NULL,   -- DNI / CE / RUC
    nro_documento           VARCHAR(15)     NOT NULL,
    fecha_nacimiento        DATE            NULL,
    edad                    TINYINT         NULL,
    genero                  CHAR(1)         NULL,       -- M / F / O
    distrito                VARCHAR(80)     NULL,
    departamento            VARCHAR(80)     NULL,
    nivel_educativo         VARCHAR(40)     NULL,
    -- Segmentación
    segmento_cliente        VARCHAR(30)     NOT NULL,   -- Nuevo / Activo / En riesgo / Dormido / Recuperado
    nivel_riesgo            VARCHAR(20)     NOT NULL,   -- Bajo / Medio / Alto / Muy Alto
    score_credito           SMALLINT        NULL,       -- 300 – 950
    -- Adquisición
    canal_adquisicion       VARCHAR(40)     NULL,
    -- Onboarding
    fecha_registro          DATE            NOT NULL,
    fecha_primer_transaccion DATE           NULL,
    -- SCD Tipo 2
    fecha_inicio_vigencia   DATE            NOT NULL,
    fecha_fin_vigencia      DATE            NULL,       -- NULL = registro actual
    es_registro_actual      BIT             NOT NULL DEFAULT 1,
    CONSTRAINT PK_dim_cliente PRIMARY KEY (cliente_sk)
);
GO

CREATE INDEX IX_dim_cliente_id     ON dim.cliente (cliente_id);
CREATE INDEX IX_dim_cliente_actual ON dim.cliente (cliente_id, es_registro_actual);
GO

-- ------------------------------------------------------------
--  dim.producto
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim.producto;
CREATE TABLE dim.producto (
    producto_sk         INT             NOT NULL IDENTITY(1,1),
    producto_id         VARCHAR(20)     NOT NULL,
    nombre_producto     VARCHAR(100)    NOT NULL,
    tipo_producto       VARCHAR(40)     NOT NULL,   -- Préstamo / Pago / Transferencia / Recarga
    categoria           VARCHAR(60)     NULL,
    moneda              CHAR(3)         NOT NULL DEFAULT 'PEN',
    plazo_dias          SMALLINT        NULL,
    tea_referencial     DECIMAL(6,4)    NULL,
    monto_minimo        DECIMAL(12,2)   NULL,
    monto_maximo        DECIMAL(12,2)   NULL,
    esta_activo         BIT             NOT NULL DEFAULT 1,
    fecha_lanzamiento   DATE            NULL,
    CONSTRAINT PK_dim_producto PRIMARY KEY (producto_sk)
);
GO

-- ------------------------------------------------------------
--  dim.comercio
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim.comercio;
CREATE TABLE dim.comercio (
    comercio_sk         INT             NOT NULL IDENTITY(1,1),
    comercio_id         VARCHAR(20)     NOT NULL,
    nombre_comercio     VARCHAR(150)    NOT NULL,
    ruc                 CHAR(11)        NULL,
    rubro               VARCHAR(80)     NOT NULL,
    categoria_rubro     VARCHAR(60)     NULL,
    tamanio_comercio    VARCHAR(20)     NOT NULL,   -- Micro / Pequeño / Mediano / Grande
    distrito            VARCHAR(80)     NULL,
    departamento        VARCHAR(80)     NULL,
    mdr_porcentaje      DECIMAL(5,4)    NULL,       -- Comisión cobrada al comercio
    esta_activo         BIT             NOT NULL DEFAULT 1,
    fecha_afiliacion    DATE            NULL,
    CONSTRAINT PK_dim_comercio PRIMARY KEY (comercio_sk)
);
GO

-- ------------------------------------------------------------
--  dim.canal
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim.canal;
CREATE TABLE dim.canal (
    canal_sk            INT             NOT NULL IDENTITY(1,1),
    canal_id            VARCHAR(20)     NOT NULL,
    nombre_canal        VARCHAR(60)     NOT NULL,
    tipo_canal          VARCHAR(40)     NOT NULL,   -- Digital / Presencial / Mixto
    plataforma          VARCHAR(40)     NULL,
    costo_operativo_sol DECIMAL(8,4)    NULL,
    CONSTRAINT PK_dim_canal PRIMARY KEY (canal_sk)
);
GO

-- ------------------------------------------------------------
--  dim.estado_prestamo
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim.estado_prestamo;
CREATE TABLE dim.estado_prestamo (
    estado_sk               INT             NOT NULL IDENTITY(1,1),
    estado_id               VARCHAR(20)     NOT NULL,
    nombre_estado           VARCHAR(60)     NOT NULL,
    categoria_sbs           VARCHAR(20)     NULL,       -- Normal / CPP / Deficiente / Dudoso / Pérdida
    rango_dpd_min           SMALLINT        NULL,
    rango_dpd_max           SMALLINT        NULL,       -- NULL = ilimitado
    requiere_provision      BIT             NOT NULL DEFAULT 0,
    porcentaje_provision    DECIMAL(5,4)    NULL,
    es_estado_final         BIT             NOT NULL DEFAULT 0,
    CONSTRAINT PK_dim_estado_prestamo PRIMARY KEY (estado_sk)
);
GO

-- ============================================================
--  3. TABLAS DE HECHOS
-- ============================================================

-- ------------------------------------------------------------
--  fact.transacciones
--  Granularidad: 1 fila = 1 transacción ejecutada
--  Cubre: pagos QR, transferencias P2P, recargas de saldo
-- ------------------------------------------------------------
DROP TABLE IF EXISTS fact.transacciones;
CREATE TABLE fact.transacciones (
    transaccion_sk          BIGINT          NOT NULL IDENTITY(1,1),
    -- FK a dimensiones
    tiempo_sk               INT             NOT NULL,
    cliente_sk              INT             NOT NULL,
    producto_sk             INT             NOT NULL,
    comercio_sk             INT             NOT NULL,   -- -1 si es transferencia P2P sin comercio
    canal_sk                INT             NOT NULL,
    -- Clave del sistema fuente (dimensión degenerada)
    transaccion_id          VARCHAR(40)     NOT NULL,
    -- Métricas aditivas
    monto_sol               DECIMAL(14,2)   NOT NULL,
    comision_sol            DECIMAL(10,4)   NOT NULL DEFAULT 0,
    costo_operativo_sol     DECIMAL(10,4)   NOT NULL DEFAULT 0,
    margen_sol              AS (comision_sol - costo_operativo_sol) PERSISTED,
    -- Atributos descriptivos
    estado_transaccion      VARCHAR(30)     NOT NULL,   -- Exitosa / Fallida / Revertida
    motivo_fallo            VARCHAR(100)    NULL,
    hora_transaccion        TIME(0)         NOT NULL,
    tiempo_respuesta_ms     SMALLINT        NULL,
    es_primera_transaccion  BIT             NOT NULL DEFAULT 0,
    CONSTRAINT PK_fact_transacciones PRIMARY KEY (transaccion_sk),
    CONSTRAINT FK_ftrans_tiempo    FOREIGN KEY (tiempo_sk)   REFERENCES dim.tiempo    (tiempo_sk),
    CONSTRAINT FK_ftrans_cliente   FOREIGN KEY (cliente_sk)  REFERENCES dim.cliente   (cliente_sk),
    CONSTRAINT FK_ftrans_producto  FOREIGN KEY (producto_sk) REFERENCES dim.producto  (producto_sk),
    CONSTRAINT FK_ftrans_comercio  FOREIGN KEY (comercio_sk) REFERENCES dim.comercio  (comercio_sk),
    CONSTRAINT FK_ftrans_canal     FOREIGN KEY (canal_sk)    REFERENCES dim.canal     (canal_sk)
);
GO

CREATE INDEX IX_ftrans_tiempo    ON fact.transacciones (tiempo_sk);
CREATE INDEX IX_ftrans_cliente   ON fact.transacciones (cliente_sk);
CREATE INDEX IX_ftrans_producto  ON fact.transacciones (producto_sk);
CREATE INDEX IX_ftrans_id_fuente ON fact.transacciones (transaccion_id);
GO

-- ------------------------------------------------------------
--  fact.prestamos
--  Granularidad: 1 fila = estado de un préstamo en un snapshot mensual
--  Permite: vintage analysis, DPD tracking, rentabilidad por cohorte
-- ------------------------------------------------------------
DROP TABLE IF EXISTS fact.prestamos;
CREATE TABLE fact.prestamos (
    prestamo_sk             BIGINT          NOT NULL IDENTITY(1,1),
    -- FK a dimensiones
    tiempo_sk               INT             NOT NULL,   -- Fecha del snapshot mensual
    cliente_sk              INT             NOT NULL,
    producto_sk             INT             NOT NULL,
    canal_sk                INT             NOT NULL,
    estado_sk               INT             NOT NULL,
    -- Dimensión degenerada
    prestamo_id             VARCHAR(40)     NOT NULL,
    -- Cohorte de originación (vital para vintage)
    tiempo_desembolso_sk    INT             NOT NULL,
    -- Métricas
    monto_desembolsado_sol  DECIMAL(14,2)   NOT NULL,
    saldo_capital_sol       DECIMAL(14,2)   NOT NULL,
    saldo_mora_sol          DECIMAL(14,2)   NOT NULL DEFAULT 0,
    interes_devengado_sol   DECIMAL(12,4)   NOT NULL DEFAULT 0,
    cuota_mensual_sol       DECIMAL(10,2)   NULL,
    -- Condiciones pactadas
    tea                     DECIMAL(6,4)    NOT NULL,
    plazo_pactado_dias      SMALLINT        NOT NULL,
    fecha_vencimiento       DATE            NOT NULL,
    -- Indicadores DPD y comportamiento
    dpd                     SMALLINT        NOT NULL DEFAULT 0,
    nro_cuotas_total        TINYINT         NULL,
    nro_cuotas_pagadas      TINYINT         NULL,
    nro_cuotas_mora         TINYINT         NOT NULL DEFAULT 0,
    -- Flags de ciclo de vida
    es_primer_prestamo      BIT             NOT NULL DEFAULT 0,
    fue_refinanciado        BIT             NOT NULL DEFAULT 0,
    fue_castigado           BIT             NOT NULL DEFAULT 0,
    CONSTRAINT PK_fact_prestamos PRIMARY KEY (prestamo_sk),
    CONSTRAINT FK_fprest_tiempo      FOREIGN KEY (tiempo_sk)            REFERENCES dim.tiempo         (tiempo_sk),
    CONSTRAINT FK_fprest_tiempo_orig FOREIGN KEY (tiempo_desembolso_sk) REFERENCES dim.tiempo         (tiempo_sk),
    CONSTRAINT FK_fprest_cliente     FOREIGN KEY (cliente_sk)           REFERENCES dim.cliente        (cliente_sk),
    CONSTRAINT FK_fprest_producto    FOREIGN KEY (producto_sk)          REFERENCES dim.producto       (producto_sk),
    CONSTRAINT FK_fprest_canal       FOREIGN KEY (canal_sk)             REFERENCES dim.canal          (canal_sk),
    CONSTRAINT FK_fprest_estado      FOREIGN KEY (estado_sk)            REFERENCES dim.estado_prestamo(estado_sk)
);
GO

CREATE INDEX IX_fprest_tiempo      ON fact.prestamos (tiempo_sk);
CREATE INDEX IX_fprest_cliente     ON fact.prestamos (cliente_sk);
CREATE INDEX IX_fprest_desembolso  ON fact.prestamos (tiempo_desembolso_sk);
CREATE INDEX IX_fprest_id_fuente   ON fact.prestamos (prestamo_id);
CREATE INDEX IX_fprest_dpd         ON fact.prestamos (dpd);
GO

-- ============================================================
--  4. DATOS SEMILLA — Catálogos pequeños
-- ============================================================

INSERT INTO dim.canal (canal_id, nombre_canal, tipo_canal, plataforma, costo_operativo_sol)
VALUES
    ('CH001', 'App Móvil Android',    'Digital',    'Android', 0.0200),
    ('CH002', 'App Móvil iOS',        'Digital',    'iOS',     0.0200),
    ('CH003', 'Web',                  'Digital',    'Web',     0.0350),
    ('CH004', 'Pago QR',              'Presencial', 'QR',      0.0150),
    ('CH005', 'Agente Corresponsal',  'Presencial', 'Agente',  0.1500),
    ('CH006', 'USSD',                 'Mixto',      'USSD',    0.0800);
GO

INSERT INTO dim.estado_prestamo
    (estado_id, nombre_estado, categoria_sbs, rango_dpd_min, rango_dpd_max,
     requiere_provision, porcentaje_provision, es_estado_final)
VALUES
    ('EP01', 'Al día',        'Normal',      0,   0,    0, 0.0100, 0),
    ('EP02', 'Mora temprana', 'CPP',         1,   30,   1, 0.0500, 0),
    ('EP03', 'Mora media',    'Deficiente',  31,  60,   1, 0.2500, 0),
    ('EP04', 'Mora grave',    'Dudoso',      61,  120,  1, 0.6000, 0),
    ('EP05', 'Castigado',     'Pérdida',     121, NULL, 1, 1.0000, 1),
    ('EP06', 'Pagado',        NULL,          0,   0,    0, 0.0000, 1),
    ('EP07', 'Refinanciado',  'CPP',         1,   30,   1, 0.0500, 0);
GO

-- ============================================================
--  FIN DEL SCRIPT DDL — FinPulse DWH v1.0
-- ============================================================
