# FinPulse DW — Data Warehouse Fintech en SQL Server

Data Warehouse completo para una fintech peruana ficticia:
modelado dimensional en esquema constelación, generación
sintética de datos con Python y 24 consultas analíticas
que cubren riesgo crediticio, rentabilidad y comportamiento
de cliente.

---

## Stack

![SQL Server](https://img.shields.io/badge/SQL_Server-2022-CC2927?style=flat&logo=microsoftsqlserver&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=flat&logo=python&logoColor=white)
![Pandas](https://img.shields.io/badge/Pandas-ETL-150458?style=flat&logo=pandas&logoColor=white)

---

## Objetivo

Simular el entorno analítico de una fintech peruana,
construyendo un Data Warehouse con datos sintéticos
realistas y consultas que respondan preguntas de negocio
sobre cartera crediticia, rentabilidad por producto
y retención de clientes.

---

## Arquitectura



## Modelo de datos — Esquema Constelación

El DW implementa dos tablas de hechos con dimensiones
compartidas y manejo de cambios históricos con SCD Tipo 2.

| Tabla | Tipo | Descripción |
|---|---|---|
| `fact_creditos` | Fact | Operaciones crediticias activas e históricas |
| `fact_pagos` | Fact | Registro de pagos y comportamiento de mora |
| `dim_cliente` | Dimensión SCD2 | Datos del cliente con historial de cambios |
| `dim_producto` | Dimensión | Tipos de crédito y condiciones |
| `dim_tiempo` | Dimensión | Tabla de fechas para análisis temporal |
| `dim_canal` | Dimensión | Canal de originación del crédito |

→ Ver diagrama completo en `diagrams/constellation_schema.png`

---

## Contenido

| Carpeta | Archivo | Descripción |
|---|---|---|
| `data/` | `generate_data.py` | Generador y carga de datos sintéticos |
| `sql/` | `ddl_schema.sql` | DDL completo: tablas, PKs, FKs e índices |
| `sql/` | `analytical_queries.sql` | 24 consultas analíticas |
| `diagrams/` | `constellation_schema.png` | Diagrama del esquema constelación |

---

## Consultas analíticas (24)

Las consultas están organizadas en cuatro bloques temáticos:

### Riesgo Crediticio
Análisis de mora por DPD (Days Past Due), tasa de default
por segmento, evolución de la cartera vencida y
concentración de riesgo por producto y canal.

### Análisis Vintage
Seguimiento de cohortes de créditos originados en el
mismo período para comparar su comportamiento de pago
a lo largo del tiempo e identificar patrones de deterioro.

### Rentabilidad
Cálculo de TEA efectiva por producto, MDR (Merchant
Discount Rate), margen por segmento de cliente y
contribución de cada canal a la rentabilidad total.

### Comportamiento de Cliente
Segmentación RFM adaptada a fintech, CLV (Customer
Lifetime Value), análisis de retención por cohorte
y probabilidad de prepago.

→ Ver todas las consultas en `sql/analytical_queries.sql`

---

## Cómo ejecutar

```bash
# 1. Instalar dependencias
pip install pandas sqlalchemy pyodbc faker

# 2. Configurar servidor en config.py
cp config.example.py config.py

# 3. Generar y cargar datos sintéticos
python data/generate_data.py

# 4. Ejecutar DDL en SQL Server
# Abrir sql/ddl_schema.sql en SSMS y ejecutar

# 5. Correr consultas analíticas
# Abrir sql/analytical_queries.sql en SSMS
```

> Requiere SQL Server con Windows Authentication
> y ODBC Driver 18 for SQL Server instalado.

---

## Conceptos clave implementados

| Concepto | Descripción |
|---|---|
| SCD Tipo 2 | Historial de cambios en dimensión cliente |
| DPD | Days Past Due — métrica estándar de mora |
| Vintage Analysis | Cohortes de originación para seguimiento de cartera |
| TEA | Tasa Efectiva Anual por producto |
| MDR | Merchant Discount Rate |
| RFM Fintech | Recency, Frequency, Monetary adaptado a créditos |
| CLV | Customer Lifetime Value por segmento |

---

## Autor

**Diego Torres Andrade**
Estudiante de Ingeniería de Sistemas — UPN Lima
Orientado a Data Analytics & Business Intelligence

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Conectar-0A66C2?style=flat&logo=linkedin)](https://linkedin.com/in/tu-usuario)
[![Portfolio](https://img.shields.io/badge/Portfolio-Ver_más-1a1a2e?style=flat)](https://tu-portfolio.vercel.app)
