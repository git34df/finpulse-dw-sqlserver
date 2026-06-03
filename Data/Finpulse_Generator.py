"""
FinPulse DWH — Generador de datos sintéticos
=============================================
Volumen  : 5 000 transacciones · 1 000 préstamos (snapshot mensual)
Salida   : Carga directa a SQL Server vía pyodbc
Período  : 2022-01-01 → 2024-12-31
Autor    : FinPulse Analytics

Dependencias:
    pip install faker pandas numpy pyodbc
"""

import random
import math
from datetime import date, datetime, timedelta




from faker import Faker


try:
    import pyodbc
    PYODBC_OK = True
except ImportError:
    PYODBC_OK = False
    print("[AVISO] pyodbc no está instalado. Ejecuta: pip install pyodbc")

# ─────────────────────────────────────────────
#  CONFIGURACIÓN GENERAL
# ─────────────────────────────────────────────
random.seed(42)

fake = Faker("es_ES")   
Faker.seed(42)

CONN_STR = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=;"          
    "DATABASE=;"
    "Trusted_Connection=yes;"   
    "TrustServerCertificate=yes;"
)

N_CLIENTES      = 800
N_COMERCIOS     = 120
N_TRANSACCIONES = 5_000
N_PRESTAMOS     = 1_000        
FECHA_INICIO    = date(2022, 1, 1)
FECHA_FIN       = date(2024, 12, 31)

# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────
def fecha_aleatoria(inicio: date, fin: date) -> date:
    delta = (fin - inicio).days
    return inicio + timedelta(days=random.randint(0, delta))

def sk_fecha(d: date) -> int:
    """Convierte date a surrogate key YYYYMMDD."""
    return int(d.strftime("%Y%m%d"))

def fechas_en_rango(inicio: date, fin: date):
    """Genera todas las fechas entre inicio y fin."""
    actual = inicio
    while actual <= fin:
        yield actual
        actual += timedelta(days=1)

FERIADOS_PERU = {
    date(2022, 1, 1), date(2022, 4, 14), date(2022, 4, 15),
    date(2022, 5, 1), date(2022, 6, 29), date(2022, 7, 28),
    date(2022, 7, 29), date(2022, 8, 30), date(2022, 10, 8),
    date(2022, 11, 1), date(2022, 12, 8), date(2022, 12, 25),
    date(2023, 1, 1), date(2023, 4, 6), date(2023, 4, 7),
    date(2023, 5, 1), date(2023, 6, 29), date(2023, 7, 28),
    date(2023, 7, 29), date(2023, 8, 30), date(2023, 10, 8),
    date(2023, 11, 1), date(2023, 12, 8), date(2023, 12, 25),
    date(2024, 1, 1), date(2024, 3, 28), date(2024, 3, 29),
    date(2024, 5, 1), date(2024, 6, 29), date(2024, 7, 28),
    date(2024, 7, 29), date(2024, 8, 30), date(2024, 10, 8),
    date(2024, 11, 1), date(2024, 12, 8), date(2024, 12, 25),
}

NOMBRE_MESES = [
    "", "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
    "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
]
NOMBRE_DIAS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

# ─────────────────────────────────────────────
#  1. dim.tiempo
# ─────────────────────────────────────────────
def generar_dim_tiempo() -> list[dict]:
    rows = []
    for d in fechas_en_rango(FECHA_INICIO, FECHA_FIN):
        dow   = d.weekday()           # 0=lun, 6=dom
        es_fm = (d == (d.replace(day=1) + timedelta(days=32)).replace(day=1) - timedelta(days=1))
        rows.append({
            "tiempo_sk":       sk_fecha(d),
            "fecha":           d,
            "anio":            d.year,
            "trimestre":       math.ceil(d.month / 3),
            "mes":             d.month,
            "nombre_mes":      NOMBRE_MESES[d.month],
            "semana_anio":     int(d.strftime("%V")),
            "dia_mes":         d.day,
            "dia_semana":      dow + 1,        # 1=lun, 7=dom
            "nombre_dia":      NOMBRE_DIAS[dow],
            "es_fin_semana":   1 if dow >= 5 else 0,
            "es_feriado_peru": 1 if d in FERIADOS_PERU else 0,
            "nombre_feriado":  None,
            "es_quincena":     1 if d.day in (15,) or es_fm else 0,
            "es_fin_mes":      1 if es_fm else 0,
        })
    print(f"  dim.tiempo         : {len(rows):>6} filas")
    return rows

# ─────────────────────────────────────────────
#  2. dim.cliente  (con SCD Tipo 2 simplificado)
# ─────────────────────────────────────────────
DISTRITOS = [
    "Miraflores", "San Isidro", "Surco", "La Molina", "San Borja",
    "Barranco", "Lince", "Jesús María", "Pueblo Libre", "Magdalena",
    "Callao", "San Martín de Porres", "Los Olivos", "Comas",
    "Villa El Salvador", "San Juan de Lurigancho", "Ate", "Carabayllo",
]
DEPTOS = ["Lima", "Arequipa", "Cusco", "Trujillo", "Piura"]
SEGMENTOS = ["Nuevo", "Activo", "En riesgo", "Dormido", "Recuperado"]
NIVELES_RIESGO = ["Bajo", "Medio", "Alto", "Muy Alto"]
EDUCACION = ["Secundaria", "Superior técnica", "Superior universitaria", "Posgrado"]
CANALES_ADQ = ["Orgánico", "Referido", "Campaña digital", "Agente"]

def generar_dim_cliente() -> list[dict]:
    rows = []
    sk = 1
    for i in range(1, N_CLIENTES + 1):
        cliente_id   = f"CLI{i:05d}"
        fecha_reg    = fecha_aleatoria(FECHA_INICIO, date(2024, 6, 30))
        score        = random.randint(300, 950)
        nivel_riesgo = (
            "Bajo" if score >= 750 else
            "Medio" if score >= 600 else
            "Alto" if score >= 450 else "Muy Alto"
        )
        segmento = random.choices(
            SEGMENTOS, weights=[15, 50, 15, 12, 8], k=1
        )[0]
        nacimiento = fecha_aleatoria(date(1970, 1, 1), date(2002, 12, 31))
        edad = (date.today() - nacimiento).days // 365

        base = dict(
            cliente_id           = cliente_id,
            nombre               = fake.first_name(),
            apellido             = fake.last_name(),
            tipo_documento       = "DNI",
            nro_documento        = str(random.randint(10_000_000, 99_999_999)),
            fecha_nacimiento     = nacimiento,
            edad                 = edad,
            genero               = random.choice(["M", "F"]),
            distrito             = random.choice(DISTRITOS),
            departamento         = random.choices(
                DEPTOS, weights=[70, 10, 8, 7, 5], k=1
            )[0],
            nivel_educativo      = random.choice(EDUCACION),
            segmento_cliente     = segmento,
            nivel_riesgo         = nivel_riesgo,
            score_credito        = score,
            canal_adquisicion    = random.choice(CANALES_ADQ),
            fecha_registro       = fecha_reg,
            fecha_primer_transaccion = fecha_reg + timedelta(days=random.randint(0, 30)),
        )

        # Registro inicial (vigente desde fecha_reg)
        rows.append({
            **base,
            "fecha_inicio_vigencia": fecha_reg,
            "fecha_fin_vigencia":    None,
            "es_registro_actual":    1,
        })
        sk += 1

        # ~20% de clientes tienen un cambio de segmento/riesgo (SCD Tipo 2)
        if random.random() < 0.20 and fecha_reg < date(2024, 1, 1):
            fecha_cambio = fecha_reg + timedelta(days=random.randint(180, 540))
            if fecha_cambio <= FECHA_FIN:
                # Cerrar registro anterior
                rows[-1]["fecha_fin_vigencia"]  = fecha_cambio - timedelta(days=1)
                rows[-1]["es_registro_actual"]  = 0
                # Nuevo registro
                nuevo_segmento = random.choice([s for s in SEGMENTOS if s != segmento])
                nuevo_score    = max(300, min(950, score + random.randint(-100, 100)))
                nuevo_riesgo   = (
                    "Bajo" if nuevo_score >= 750 else
                    "Medio" if nuevo_score >= 600 else
                    "Alto" if nuevo_score >= 450 else "Muy Alto"
                )
                rows.append({
                    **base,
                    "segmento_cliente":      nuevo_segmento,
                    "nivel_riesgo":          nuevo_riesgo,
                    "score_credito":         nuevo_score,
                    "fecha_inicio_vigencia": fecha_cambio,
                    "fecha_fin_vigencia":    None,
                    "es_registro_actual":    1,
                })
                sk += 1

    print(f"  dim.cliente        : {len(rows):>6} filas  ({N_CLIENTES} clientes, ~20% con versión SCD2)")
    return rows

# ─────────────────────────────────────────────
#  3. dim.producto
# ─────────────────────────────────────────────
PRODUCTOS_SEED = [
    ("PRD001", "Préstamo Express 30d",   "Préstamo",      "Express",   30,  1.8500, 100,    1_000),
    ("PRD002", "Préstamo Express 60d",   "Préstamo",      "Express",   60,  1.6200, 200,    3_000),
    ("PRD003", "Préstamo Personal 6m",   "Préstamo",      "Personal",  180, 0.9800, 500,   10_000),
    ("PRD004", "Préstamo Personal 12m",  "Préstamo",      "Personal",  360, 0.8500, 1_000, 20_000),
    ("PRD005", "Pago QR Comercio",       "Pago",          "QR",        None, None,  1,     5_000),
    ("PRD006", "Transferencia P2P",      "Transferencia", "P2P",       None, None,  1,    10_000),
    ("PRD007", "Recarga de Saldo",       "Recarga",       "Digital",   None, None,  10,    500),
    ("PRD008", "Pago de Servicios",      "Pago",          "Servicios", None, None,  20,    500),
]

def generar_dim_producto() -> list[dict]:
    rows = []
    for r in PRODUCTOS_SEED:
        rows.append({
            "producto_id":       r[0],
            "nombre_producto":   r[1],
            "tipo_producto":     r[2],
            "categoria":         r[3],
            "moneda":            "PEN",
            "plazo_dias":        r[4],
            "tea_referencial":   r[5],
            "monto_minimo":      r[6],
            "monto_maximo":      r[7],
            "esta_activo":       1,
            "fecha_lanzamiento": date(2022, 1, 1),
        })
    print(f"  dim.producto       : {len(rows):>6} filas")
    return rows

# ─────────────────────────────────────────────
#  4. dim.comercio
# ─────────────────────────────────────────────
RUBROS = [
    ("Restaurante",   "Alimentos",  0.0250),
    ("Farmacia",      "Salud",      0.0150),
    ("Bodega",        "Alimentos",  0.0100),
    ("Supermercado",  "Retail",     0.0080),
    ("Ropa y Moda",   "Retail",     0.0200),
    ("Electrónica",   "Tecnología", 0.0180),
    ("Transporte",    "Servicios",  0.0120),
    ("Educación",     "Servicios",  0.0150),
    ("Entretenimiento","Ocio",      0.0220),
    ("Ferretería",    "Retail",     0.0130),
]
TAMANIOS = ["Micro", "Pequeño", "Mediano", "Grande"]

def generar_dim_comercio() -> list[dict]:
    rows = []
    for i in range(1, N_COMERCIOS + 1):
        rubro_info  = random.choice(RUBROS)
        tamanio     = random.choices(TAMANIOS, weights=[50, 30, 15, 5], k=1)[0]
        rows.append({
            "comercio_id":      f"COM{i:04d}",
            "nombre_comercio":  fake.company(),
            "ruc":              str(random.randint(10_000_000_000, 19_999_999_999)),
            "rubro":            rubro_info[0],
            "categoria_rubro":  rubro_info[1],
            "tamanio_comercio": tamanio,
            "distrito":         random.choice(DISTRITOS),
            "departamento":     random.choices(DEPTOS, weights=[70,10,8,7,5], k=1)[0],
            "mdr_porcentaje":   rubro_info[2],
            "esta_activo":      1,
            "fecha_afiliacion": fecha_aleatoria(FECHA_INICIO, date(2022, 6, 30)),
        })
    # Registro especial -1 para transferencias P2P sin comercio
    rows.insert(0, {
        "comercio_id":      "COM0000",
        "nombre_comercio":  "Sin comercio (P2P)",
        "ruc":              None,
        "rubro":            "N/A",
        "categoria_rubro":  "N/A",
        "tamanio_comercio": "Micro",
        "distrito":         None,
        "departamento":     None,
        "mdr_porcentaje":   0.0,
        "esta_activo":      1,
        "fecha_afiliacion": FECHA_INICIO,
    })
    print(f"  dim.comercio       : {len(rows):>6} filas")
    return rows

# ─────────────────────────────────────────────
#  5. fact.transacciones
# ─────────────────────────────────────────────
ESTADOS_TX = ["Exitosa", "Fallida", "Revertida"]
MOTIVOS_FALLO = [
    "Saldo insuficiente", "Error de red", "Límite diario excedido",
    "Cuenta bloqueada", "Timeout", "Datos inválidos",
]

def generar_fact_transacciones(
    clientes: list[dict],
    productos: list[dict],
    comercios: list[dict],
    canales_sk: list[int],
    tiempo_sks: set[int],
) -> list[dict]:

    # Solo clientes actuales para generar transacciones
    clientes_actuales = [c for c in clientes if c["es_registro_actual"] == 1]
    prods_pago  = [p for p in productos if p["tipo_producto"] in ("Pago", "Transferencia", "Recarga")]
    com_p2p_sk  = 1   # comercio COM0000 es el primero insertado → sk=1
    comercio_ids = [c["comercio_id"] for c in comercios if c["comercio_id"] != "COM0000"]

    rows = []
    for i in range(1, N_TRANSACCIONES + 1):
        cliente   = random.choice(clientes_actuales)
        producto  = random.choice(prods_pago)
        fecha_tx  = fecha_aleatoria(
            max(FECHA_INICIO, cliente["fecha_registro"]),
            FECHA_FIN
        )

        # Efecto quincena: más volumen los días 15 y fin de mes
        if fecha_tx.day in (15, 30, 31) or (fecha_tx.day == 28 and fecha_tx.month == 2):
            if random.random() < 0.35:
                continue   # reemplaza con otra fecha (ya hay más densidad)

        sk_t  = sk_fecha(fecha_tx)
        if sk_t not in tiempo_sks:
            continue

        # Comercio: P2P sin comercio vs comercio real
        if producto["tipo_producto"] == "Transferencia":
            com_sk = com_p2p_sk
        else:
            com_sk = random.randint(2, N_COMERCIOS + 1)  # sk de comercio real

        monto = round(random.uniform(
            float(producto["monto_minimo"]),
            min(float(producto["monto_maximo"]), 500.0)
        ), 2)

        estado = random.choices(ESTADOS_TX, weights=[88, 8, 4], k=1)[0]
        mdr    = random.uniform(0.008, 0.025) if estado == "Exitosa" else 0.0
        comision = round(monto * mdr, 4) if estado == "Exitosa" else 0.0
        costo_op = round(random.uniform(0.01, 0.15), 4)
        hora_tx  = datetime.strptime(
            f"{random.randint(6,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}",
            "%H:%M:%S"
        ).time()

        rows.append({
            "tiempo_sk":             sk_t,
            "cliente_sk":            clientes_actuales.index(cliente) + 1,
            "producto_sk":           prods_pago.index(producto) + 5,  # PRD005..008
            "comercio_sk":           com_sk,
            "canal_sk":              random.choice(canales_sk),
            "transaccion_id":        f"TXN{i:07d}",
            "monto_sol":             monto,
            "comision_sol":          comision,
            "costo_operativo_sol":   costo_op,
            "estado_transaccion":    estado,
            "motivo_fallo":          random.choice(MOTIVOS_FALLO) if estado != "Exitosa" else None,
            "hora_transaccion":      hora_tx,
            "tiempo_respuesta_ms":   random.randint(80, 3500),
            "es_primera_transaccion": 1 if i <= N_CLIENTES else 0,
        })

    print(f"  fact.transacciones : {len(rows):>6} filas")
    return rows

# ─────────────────────────────────────────────
#  6. fact.prestamos  (snapshot mensual)
# ─────────────────────────────────────────────
# Estados  sk: 1=Al día, 2=Mora temprana, 3=Mora media,
#              4=Mora grave, 5=Castigado, 6=Pagado, 7=Refinanciado
def dpd_a_estado_sk(dpd: int, pagado: bool, castigado: bool) -> int:
    if pagado:   return 6
    if castigado or dpd > 120: return 5
    if dpd == 0: return 1
    if dpd <= 30: return 2
    if dpd <= 60: return 3
    return 4

def generar_fact_prestamos(
    clientes: list[dict],
    productos: list[dict],
    canales_sk: list[int],
    tiempo_sks: set[int],
) -> list[dict]:

    clientes_actuales = [c for c in clientes if c["es_registro_actual"] == 1]
    prods_prestamo    = [p for p in productos if p["tipo_producto"] == "Préstamo"]

    rows = []
    prestamo_counter = 0

    while prestamo_counter < N_PRESTAMOS:
        cliente  = random.choice(clientes_actuales)
        producto = random.choice(prods_prestamo)
        cli_sk   = clientes_actuales.index(cliente) + 1
        prod_sk  = next(
            i + 1 for i, p in enumerate(productos) if p["producto_id"] == producto["producto_id"]
        )

        # Fecha de desembolso
        fecha_desembolso = fecha_aleatoria(
            max(FECHA_INICIO, cliente["fecha_registro"]),
            date(2024, 6, 30)   # dejar margen para snapshots
        )
        sk_desembolso = sk_fecha(fecha_desembolso)
        if sk_desembolso not in tiempo_sks:
            continue

        monto  = round(random.uniform(
            float(producto["monto_minimo"]),
            float(producto["monto_maximo"])
        ), 2)
        tea    = round(float(producto["tea_referencial"]) + random.uniform(-0.05, 0.15), 4)
        plazo  = int(producto["plazo_dias"])
        fecha_venc = fecha_desembolso + timedelta(days=plazo)
        cuota  = round(monto * (tea / 12) / (1 - (1 + tea / 12) ** -max(1, plazo // 30)), 2)

        # Simular comportamiento de pago mes a mes
        dpd_acum     = 0
        saldo        = monto
        pagado       = False
        castigado    = False
        fue_refinanc = random.random() < 0.05
        es_primero   = prestamo_counter < N_CLIENTES // 2

        meses_vida = max(1, plazo // 30)
        for mes_n in range(meses_vida + 3):
            fecha_snap = fecha_desembolso + timedelta(days=30 * mes_n)
            if fecha_snap > FECHA_FIN:
                break
            sk_snap = sk_fecha(fecha_snap)
            if sk_snap not in tiempo_sks:
                continue

            # Probabilidad de atraso según score del cliente
            score = cliente.get("score_credito", 600)
            prob_mora = max(0.02, 0.40 - score / 1400)

            if random.random() < prob_mora and not pagado and not castigado:
                dpd_acum += random.randint(5, 35)
            else:
                dpd_acum = max(0, dpd_acum - random.randint(0, 15))

            if dpd_acum > 120:
                castigado = True
            if mes_n >= meses_vida and dpd_acum == 0:
                pagado = True

            saldo_mora = round(saldo * (dpd_acum / 90) * 0.1, 2) if dpd_acum > 0 else 0.0
            saldo      = max(0, round(saldo - cuota * (1 - prob_mora * 0.5), 2))

            estado_sk = dpd_a_estado_sk(dpd_acum, pagado, castigado)
            cuotas_pagadas = min(mes_n, meses_vida)
            cuotas_mora    = max(0, round(dpd_acum / 30))

            rows.append({
                "tiempo_sk":             sk_snap,
                "cliente_sk":            cli_sk,
                "producto_sk":           prod_sk,
                "canal_sk":              random.choice(canales_sk),
                "estado_sk":             estado_sk,
                "prestamo_id":           f"PREST{prestamo_counter:06d}",
                "tiempo_desembolso_sk":  sk_desembolso,
                "monto_desembolsado_sol": monto,
                "saldo_capital_sol":     saldo,
                "saldo_mora_sol":        saldo_mora,
                "interes_devengado_sol": round(monto * tea / 12 * mes_n, 4),
                "cuota_mensual_sol":     cuota,
                "tea":                   tea,
                "plazo_pactado_dias":    plazo,
                "fecha_vencimiento":     fecha_venc,
                "dpd":                   dpd_acum,
                "nro_cuotas_total":      meses_vida,
                "nro_cuotas_pagadas":    cuotas_pagadas,
                "nro_cuotas_mora":       cuotas_mora,
                "es_primer_prestamo":    1 if es_primero else 0,
                "fue_refinanciado":      1 if fue_refinanc else 0,
                "fue_castigado":         1 if castigado else 0,
            })

            if pagado or castigado:
                break

        prestamo_counter += 1

    print(f"  fact.prestamos     : {len(rows):>6} filas  ({N_PRESTAMOS} préstamos × snapshots mensuales)")
    return rows

# ─────────────────────────────────────────────
#  7. CARGA A SQL SERVER
# ─────────────────────────────────────────────
def bulk_insert(cursor, tabla: str, columnas: list[str], filas: list[dict], batch: int = 500):
    """Inserta filas en lotes usando executemany."""
    placeholders = ", ".join(["?"] * len(columnas))
    sql = f"INSERT INTO {tabla} ({', '.join(columnas)}) VALUES ({placeholders})"
    data = [[row.get(c) for c in columnas] for row in filas]
    for inicio in range(0, len(data), batch):
        cursor.executemany(sql, data[inicio:inicio + batch])
    print(f"    ✓ {tabla:<40} {len(filas):>6} filas insertadas")

def leer_canales_sk(cursor) -> list[int]:
    """Lee los canal_sk reales que existen en dim.canal."""
    cursor.execute("SELECT canal_sk FROM dim.canal ORDER BY canal_sk")
    sks = [row[0] for row in cursor.fetchall()]
    if not sks:
        raise ValueError("dim.canal está vacía. Asegúrate de haber ejecutado el DDL con los datos semilla.")
    print(f"    ↳ Canales encontrados en BD: {sks}")
    return sks

def leer_estados_sk(cursor) -> list[int]:
    """Lee los estado_sk reales que existen en dim.estado_prestamo."""
    cursor.execute("SELECT estado_sk FROM dim.estado_prestamo ORDER BY estado_sk")
    sks = [row[0] for row in cursor.fetchall()]
    if not sks:
        raise ValueError("dim.estado_prestamo está vacía. Ejecuta primero el DDL.")
    return sks

def cargar_a_sql(datos: dict):
    if not PYODBC_OK:
        print("\n[ERROR] pyodbc no disponible. Instálalo con: pip install pyodbc")
        return

    print("\n[CARGA SQL SERVER]")
    conn   = pyodbc.connect(CONN_STR, autocommit=False)
    cursor = conn.cursor()

    try:
        # ── 1. Limpiar tablas en orden FK-safe ──
        print("  Limpiando tablas previas...")
        # Borrar hechos primero (dependen de dimensiones)
        for tabla in ["fact.transacciones", "fact.prestamos"]:
            cursor.execute(f"DELETE FROM {tabla}")

        # Borrar dimensiones (dim.tiempo NO tiene IDENTITY, no usar RESEED)
        for tabla in ["dim.comercio", "dim.producto", "dim.cliente", "dim.tiempo"]:
            cursor.execute(f"DELETE FROM {tabla}")

        # Resetear IDENTITY solo en tablas que sí lo tienen
        for tabla in ["dim.comercio", "dim.producto", "dim.cliente"]:
            cursor.execute(f"DBCC CHECKIDENT('{tabla}', RESEED, 0)")

        # fact tables también tienen IDENTITY en su SK
        for tabla in ["fact.transacciones", "fact.prestamos"]:
            cursor.execute(f"DBCC CHECKIDENT('{tabla}', RESEED, 0)")

        conn.commit()
        print("  ✓ Tablas limpiadas y contadores IDENTITY reseteados")

        # ── 2. Leer SK reales de catálogos semilla ──
        print("  Leyendo SK reales de catálogos...")
        canales_sk_reales  = leer_canales_sk(cursor)
        estados_sk_reales  = leer_estados_sk(cursor)

        # ── 3. Reasignar SK en los hechos usando los valores reales ──
        # Los datos generados usan canales 1-6 y estados 1-7.
        # Hacemos un mapeo posicional por si los IDENTITY empezaron diferente.
        canal_map  = {i+1: sk for i, sk in enumerate(canales_sk_reales)}
        estado_map = {i+1: sk for i, sk in enumerate(estados_sk_reales)}

        for row in datos["transacciones"]:
            row["canal_sk"] = canal_map.get(row["canal_sk"], canales_sk_reales[0])
        for row in datos["prestamos"]:
            row["canal_sk"]  = canal_map.get(row["canal_sk"],  canales_sk_reales[0])
            row["estado_sk"] = estado_map.get(row["estado_sk"], estados_sk_reales[0])

        # ── 4. Insertar dimensiones ──
        bulk_insert(cursor, "dim.tiempo", [
            "tiempo_sk","fecha","anio","trimestre","mes","nombre_mes",
            "semana_anio","dia_mes","dia_semana","nombre_dia",
            "es_fin_semana","es_feriado_peru","nombre_feriado",
            "es_quincena","es_fin_mes"
        ], datos["tiempo"])

        bulk_insert(cursor, "dim.cliente", [
            "cliente_id","nombre","apellido","tipo_documento","nro_documento",
            "fecha_nacimiento","edad","genero","distrito","departamento",
            "nivel_educativo","segmento_cliente","nivel_riesgo","score_credito",
            "canal_adquisicion","fecha_registro","fecha_primer_transaccion",
            "fecha_inicio_vigencia","fecha_fin_vigencia","es_registro_actual"
        ], datos["cliente"])

        bulk_insert(cursor, "dim.producto", [
            "producto_id","nombre_producto","tipo_producto","categoria","moneda",
            "plazo_dias","tea_referencial","monto_minimo","monto_maximo",
            "esta_activo","fecha_lanzamiento"
        ], datos["producto"])

        bulk_insert(cursor, "dim.comercio", [
            "comercio_id","nombre_comercio","ruc","rubro","categoria_rubro",
            "tamanio_comercio","distrito","departamento","mdr_porcentaje",
            "esta_activo","fecha_afiliacion"
        ], datos["comercio"])

        # ── 5. Insertar hechos ──
        bulk_insert(cursor, "fact.transacciones", [
            "tiempo_sk","cliente_sk","producto_sk","comercio_sk","canal_sk",
            "transaccion_id","monto_sol","comision_sol","costo_operativo_sol",
            "estado_transaccion","motivo_fallo","hora_transaccion",
            "tiempo_respuesta_ms","es_primera_transaccion"
        ], datos["transacciones"])

        bulk_insert(cursor, "fact.prestamos", [
            "tiempo_sk","cliente_sk","producto_sk","canal_sk","estado_sk",
            "prestamo_id","tiempo_desembolso_sk","monto_desembolsado_sol",
            "saldo_capital_sol","saldo_mora_sol","interes_devengado_sol",
            "cuota_mensual_sol","tea","plazo_pactado_dias","fecha_vencimiento",
            "dpd","nro_cuotas_total","nro_cuotas_pagadas","nro_cuotas_mora",
            "es_primer_prestamo","fue_refinanciado","fue_castigado"
        ], datos["prestamos"])

        conn.commit()
        print("\n  ✅ Carga completada y commit realizado.")

    except Exception as e:
        conn.rollback()
        print(f"\n  ❌ Error durante la carga: {e}")
        raise
    finally:
        cursor.close()
        conn.close()

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────
def main():
    print("=" * 52)
    print("  FinPulse DWH — Generador de datos sintéticos")
    print("=" * 52)
    print("\n[GENERANDO DIMENSIONES Y HECHOS]")

    tiempo   = generar_dim_tiempo()
    tiempo_sks = {r["tiempo_sk"] for r in tiempo}

    cliente  = generar_dim_cliente()
    producto = generar_dim_producto()
    comercio = generar_dim_comercio()

    # Los canal_sk reales se leerán de la BD en cargar_a_sql
    # Usamos 1-6 como placeholder; se remapean antes de insertar
    canales_sk = list(range(1, 7))

    transacciones = generar_fact_transacciones(
        cliente, producto, comercio, canales_sk, tiempo_sks
    )
    prestamos = generar_fact_prestamos(
        cliente, producto, canales_sk, tiempo_sks
    )

    datos = {
        "tiempo":        tiempo,
        "cliente":       cliente,
        "producto":      producto,
        "comercio":      comercio,
        "transacciones": transacciones,
        "prestamos":     prestamos,
    }

    total = sum(len(v) for v in datos.values())
    print(f"\n  Total filas generadas: {total:,}")
    print("\n[INICIANDO CARGA A SQL SERVER]")
    print(f"  Cadena de conexión: {CONN_STR[:50]}...")

    cargar_a_sql(datos)

    print("\n[RESUMEN FINAL]")
    for tabla, filas in datos.items():
        print(f"  {tabla:<20}: {len(filas):>6} filas")
    print("\n  ¡Proyecto FinPulse DWH listo para consultas!")

if __name__ == "__main__":
    main()
