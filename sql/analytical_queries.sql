
-- Tasa de Morosidad por Segmento
SELECT dc.segmento_cliente                                              AS
       [Segmento de Cliente],
       ( Sum(fp.saldo_mora_sol) * 1.0 / Sum(fp.saldo_capital_sol) )     AS
       [Tasa de morosidad],
       Count(DISTINCT CASE
                        WHEN fp.dpd > 0 THEN fp.prestamo_id
                      END)                                              AS
       [Total Prestamos con Mora],
       Count(DISTINCT fp.prestamo_id)                                   AS
       [Total Prestamos],
       Count(DISTINCT CASE
                        WHEN fp.dpd > 0 THEN fp.prestamo_id
                      END) * 1.0 / Count(DISTINCT fp.prestamo_id) * 100 AS
       [% Prestamos Mora],
       CASE
         WHEN Count(DISTINCT CASE
                               WHEN fp.dpd > 0 THEN fp.prestamo_id
                             END) BETWEEN 20 AND 50 THEN 'Baja cantidad morosa'
         ELSE 'Alta cantidad Morosa'
       END                                                              AS
       [Segmento Morosidad]
FROM   fact.prestamos AS fp
       INNER JOIN dim.cliente AS dc
               ON fp.cliente_sk = dc.cliente_sk
GROUP  BY dc.segmento_cliente
ORDER  BY [tasa de morosidad]; 


-- Distribucion de Cartera por DPD
SELECT fp.dpd                                           AS [DPD],
       Format(Sum(fp.saldo_capital_sol), 'N0', 'es-ES') AS saldo_total,
       Sum(fp.saldo_capital_sol) * 1.0 / Sum(Sum(fp.saldo_capital_sol))
                                           OVER()       AS pct_saldo,
       CASE
         WHEN fp.dpd BETWEEN 0 AND 30 THEN 'Etapa Temprana'
         WHEN fp.dpd BETWEEN 31 AND 60 THEN 'Etapa Media'
         WHEN fp.dpd BETWEEN 61 AND 90 THEN 'Tardia'
         ELSE 'Morosidad Grave o Impago'
       END                                              AS [DPD Bucket]
FROM   fact.prestamos AS fp
GROUP  BY fp.dpd
ORDER  BY fp.dpd ASC; 

--Vintage analisis - mora por Cohorte 
with VintageBase as (
 select 
    fp.prestamo_id,
    Format(dt.fecha,'yyyy-MM') as fecha_desembolso,
    datediff(MONTH,dtd.fecha,dt.fecha) as mes_vida,
    fp.saldo_mora_sol,
    fp.saldo_capital_sol
    from fact.prestamos as fp
    inner join dim.tiempo as dtd on fp.tiempo_desembolso_sk = dtd.tiempo_sk
    inner join dim.tiempo as dt on fp.tiempo_sk = dt.tiempo_sk
),
  agrupado as (
    select
    fecha_desembolso,
    mes_vida,
    sum(saldo_mora_sol) as mora,
    sum(saldo_capital_Sol) as saldo
    from VintageBase
    group by fecha_desembolso, mes_vida
 )

 select
 fecha_desembolso,
 mes_vida,
 mora * 1.0 / nullif(saldo,0) as tasa_mora
 from agrupado
 order by fecha_desembolso,mes_vida;


 --Evolucion mensual DPD promedio por producto 
with dpd_mensual as (
select
dp.tipo_producto,
dt.anio,
dt.mes,
avg(fp.dpd) as dpd_promedio_mes
from fact.prestamos as fp
inner join dim.producto as dp on fp.producto_sk=dp.producto_sk
inner join dim.tiempo as dt on fp.tiempo_sk=dt.tiempo_sk
where dp.tipo_producto= 'Préstamo'
group by dp.tipo_producto,dt.anio,dt.mes
)
select
tipo_producto,
anio,
mes,
dpd_promedio_mes,
avg(dpd_promedio_mes) over( partition by tipo_producto order by anio, mes ROWS BETWEEN 2 PRECEDING and CURRENT ROW ) as promedio_movil_3_meses
from dpd_mensual
order by tipo_producto,anio,mes;

--Clientes con Escalada con DPD en los ultimos 3 meses 

with dpd_base as (
 select
 dt.anio,
 dt.mes,
 dt.tiempo_sk,
 fp.prestamo_id,
 concat(dc.nombre ,' ', dc.apellido) as nombre,
 avg(fp.dpd) as DPD
 from fact.prestamos as fp
 inner join dim.tiempo as dt on fp.tiempo_sk = dt.tiempo_sk
 inner join dim.cliente as dc on fp.cliente_sk = dc.cliente_sk
 where dc.es_registro_actual = 1
 group by dt.anio,dt.mes,dc.nombre,dc.apellido,fp.prestamo_id,dt.tiempo_sk
 ),
 dpd_3_snapshots as (
 select
 anio,
 mes,
 nombre,
 DPD,
 lag(DPD,1) OVER (Partition by prestamo_id ORDER BY tiempo_sk) as mes_anterior,
 lag(DPD,2) OVER (Partition by prestamo_id ORDER BY tiempo_sk) as dos_meses_atras
 from dpd_base
 )
 select
 anio,
 mes,
 nombre,
 DPD,
 mes_anterior,
 dos_meses_atras,
 case
   when DPD > mes_anterior and mes_anterior > dos_meses_atras then 'DPD Empeoro'
   when DPD < mes_anterior and mes_anterior > dos_meses_atras then 'DPD Decrecio' 
   when DPD > mes_anterior and mes_anterior < dos_meses_atras then 'DPD Volatil'
   when DPD > mes_anterior and mes_anterior = dos_meses_atras then 'DPD Primer aumento'
   else 'DPD Sin Crecimiento'
   end as categoria_dpd
  from
  dpd_3_snapshots
  where DPD > 0 and mes_anterior is not null and dos_meses_atras is not null
  order by anio,mes;

  --Ranking de Productos Por margen total
  with margen_producto as (
  select
  dp.nombre_producto as producto,
  ft.estado_transaccion,
  sum(ft.margen_sol) as margen,
  ft.comision_sol,
  ft.costo_operativo_sol
  from fact.transacciones as ft
  inner join dim.producto as dp on ft.producto_sk = dp.producto_sk
  where ft.estado_transaccion = 'Exitosa'
  group by dp.nombre_producto,ft.comision_sol,ft.costo_operativo_sol,ft.estado_transaccion
  )
  select
  producto,
  estado_transaccion,
  margen,
  comision_sol,
  costo_operativo_sol,
  rank() OVER(Partition By producto order by margen) as rank_margen
  from margen_producto
  order by rank_margen asc;

  --Rentabilidad por Canal 
  select dc.nombre_canal,dc.tipo_canal,avg(ft.margen_sol) as [Margen Promedio], COUNT(*) as volumen_transacciones 
  from fact.transacciones as ft
  inner join dim.canal as dc on ft.canal_sk=dc.canal_sk
  where ft.estado_transaccion='Exitosa'
  group by dc.nombre_canal,dc.tipo_canal
  order by volumen_transacciones desc;

  --Ingreso por comisiones acumuladas (YoY)
WITH comisiones_acumulada
     AS (SELECT dt.anio              AS año,
                dt.mes               AS mes,
                Sum(ft.comision_sol) AS comision
         FROM   fact.transacciones AS ft
                INNER JOIN dim.tiempo AS dt
                        ON ft.tiempo_sk = dt.tiempo_sk
         WHERE  ft.estado_transaccion = 'Exitosa'
         GROUP  BY dt.anio,
                   dt.mes),
     comision_lag
     AS (SELECT año,
                mes,
                comision,
                Lag(comision)
                  OVER(
                    ORDER BY año, mes) AS comision_año_pasado,
                Round(( ( comision - Lag(comision)
                                       OVER(
                                         ORDER BY año, mes) ) / Lag(comision)
                        OVER(
                          ORDER BY año, mes)
                      ), 2) *
                100                     AS comision_yoy
         FROM   comisiones_acumulada)
SELECT año,
       mes,
       comision,
       comision_año_pasado,
       comision_yoy
FROM   comision_lag
ORDER  BY año,
          mes 


-- LTV estimado por cliente 
with ingreso_total_acumulado as (
select
dc.segmento_cliente as segmento,
ft.cliente_sk,
sum(ft.comision_sol) as acumulado_comisiones
from fact.transacciones as ft
inner join dim.cliente as dc on ft.cliente_sk=dc.cliente_sk
where dc.es_registro_actual = 1 and ft.estado_transaccion = 'Exitosa'
group by dc.segmento_cliente,ft.cliente_sk
),
interes_devengado_acumulado as (
select
dc.segmento_cliente as segmento,
fp.cliente_sk,
sum(fp.interes_devengado_sol) as interes_acumulado
from fact.prestamos as fp
inner join dim.cliente as dc on fp.cliente_sk=dc.cliente_sk
where dc.es_registro_actual = 1
group by dc.segmento_cliente,fp.cliente_sk
)
select
coalesce(it.segmento,id.segmento) as segmento,
it.cliente_sk,
isnull(it.acumulado_comisiones,0)+
isnull(id.interes_acumulado,0) as ltv_estimado,
AVG (isnull(it.acumulado_comisiones,0)+
isnull(id.interes_acumulado,0)) OVER(Partition by Coalesce (it.segmento,id.segmento)) as ltv_promedio_segmento
from ingreso_total_acumulado as it
left join interes_devengado_acumulado as id on it.cliente_sk=id.cliente_sk
order by segmento,ltv_estimado desc;

-- Ticket Promedio por Rubro de comercio y dia de semana 
with base as (
select dc.rubro, dt.dia_semana, dt.nombre_dia, avg(ft.monto_sol) as ticket_promedio, 
count(*) total_transacciones
from fact.transacciones as ft
inner join dim.comercio as dc on ft.comercio_sk = dc.comercio_sk
inner join dim.tiempo as dt on ft.tiempo_sk=dt.tiempo_sk
where ft.estado_transaccion='Exitosa'
group by dc.rubro,dt.dia_semana,dt.nombre_dia
),
ranks as (
select
rubro,
nombre_dia,
dia_semana,
ticket_promedio,
total_transacciones,
Rank() OVER(Partition by nombre_dia order by ticket_promedio desc) as rank_ticket_promedio,
Rank() OVER(Partition by nombre_dia order by total_transacciones desc) as rank_volumen
from base
)
select 
rubro,
nombre_dia,
ticket_promedio,
total_transacciones,
rank_ticket_promedio,
rank_volumen,
CASE
    WHEN rank_ticket_promedio <= 3 AND rank_volumen > 3  THEN 'Ticket alto, poco volumen'
    WHEN rank_ticket_promedio > 3  AND rank_volumen <= 3 THEN 'Alto volumen, ticket bajo'
    WHEN rank_ticket_promedio <= 3 AND rank_volumen <= 3 THEN 'Top en ambos'
    ELSE 'Rubro estándar'
END AS categoria_rubro
from ranks
order by dia_semana

-- TEA efectiva Promedio por producto y nivel de riesgo de cliente 
with base as (
select dp.nombre_producto nombre, 
dc.nivel_riesgo, 
avg(fp.tea) as avg_tea, 
avg(dc.score_credito) as avg_score 
from fact.prestamos as fp
inner join dim.producto as dp on fp.producto_sk = dp.producto_sk
inner join dim.cliente as dc on fp.cliente_sk=dc.cliente_sk
group by dp.nombre_producto, dc.nivel_riesgo
),
rank_base as (
select
nombre,
nivel_riesgo,
avg_tea,
avg_score,
Rank() OVER(Partition by nombre order by avg_tea desc) as rank_avg_tea,
Rank() OVER(Partition by nombre order by avg_score desc) as rank_avg_score
from base
)
select
nombre,
nivel_riesgo,
avg_tea,
avg_score,
rank_avg_tea,
rank_avg_score
from rank_base
order by nombre

-- Segmentacion RFM de clientes transaccionales 
with rfm_base as (
select
dc.cliente_sk,
concat(dc.nombre,' ',dc.apellido) as nombre,
datediff(day,max(dt.fecha),'2024-12-31') as recencia,
count(ft.transaccion_sk) as frecuencia,
sum(ft.monto_sol) as monto
from fact.transacciones as ft
inner join dim.cliente as dc on ft.cliente_sk = dc.cliente_sk
inner join dim.tiempo as dt on ft.tiempo_sk = dt.tiempo_sk
where ft.estado_transaccion = 'Exitosa'
group by dc.nombre, dc.apellido, dc.cliente_sk
),
rfm_score as (
select *,
Ntile(3) OVER (order by recencia asc) as score_r,
Ntile(3) OVER (order by frecuencia asc) as score_f,
Ntile(3) OVER(order by monto asc) as score_m
from rfm_base)
select
nombre,
recencia,
frecuencia,
monto,
score_r,
score_f,
score_m,
CASE
         WHEN score_r = 1
              AND score_f = 1
              AND score_m = 1 THEN 'GOLDEN'
         WHEN score_r <= 2
              AND score_f <= 2
              AND score_m <= 2 THEN 'SILVER'
         ELSE 'BRONZE'
       END                              AS segmento_rfm
from rfm_score
order by monto desc;

--Cohortes de Reactivacion 
With Cohorte as ( 
select
cliente_sk,
year(fecha_registro) as año_cohorte,
month(fecha_registro) as mes_cohorte
from dim.cliente 
where es_registro_actual = 1
),
total_cohorte as ( 
select
año_cohorte,
mes_cohorte,
count(cliente_sk) as total_clientes
from Cohorte
group by año_cohorte,mes_cohorte
),
actividad as (
select
c.año_cohorte,
c.mes_cohorte,
ft.cliente_sk,
DATEDIFF( 
month,
datefromparts(c.año_cohorte,c.mes_cohorte,1),
datefromparts(dt.anio,dt.mes,1)
) as mes_relativo
from fact.transacciones as ft
inner join dim.tiempo as dt on ft.tiempo_sk = dt.tiempo_sk
inner join Cohorte as c on ft.cliente_sk=c.cliente_sk
where ft.estado_transaccion='Exitosa'
and  DATEDIFF( 
month,
datefromparts(c.año_cohorte,c.mes_cohorte,1),
datefromparts(dt.anio,dt.mes,1)
) between 0 and 12 
),
retencion as (
select 
año_cohorte,
mes_cohorte,
mes_relativo,
count(distinct cliente_sk) as clientes_activos 
from actividad
group by año_cohorte,mes_cohorte,mes_relativo
)
select 
r.año_cohorte,
r.mes_cohorte,
r.mes_relativo,
r.clientes_activos,
tc.total_clientes,
format ( 
r.clientes_activos * 100.0 / tc.total_clientes , 'N2','es-ES'
) as pct_retencion
from retencion as r 
inner join total_cohorte as tc on tc.año_cohorte = r.año_cohorte and
tc.mes_cohorte=r.mes_cohorte
order by r.año_cohorte,r.mes_cohorte,r.mes_relativo;

--Identificacion de clientes en riesgo de Churn 
with tx_mensual as (
select 
concat(dc.nombre,' ',dc.apellido) as nombre,
ft.cliente_sk,
datefromparts(year(dt.fecha),month(dt.fecha),1) as mes,
count(*) as transacciones 
from fact.transacciones as ft
inner join dim.tiempo as dt on ft.tiempo_sk=dt.tiempo_sk
inner join dim.cliente as dc on ft.cliente_sk=dc.cliente_sk
group by ft.cliente_sk,datefromparts(year(dt.fecha),month(dt.fecha),1),dc.nombre,dc.apellido
),
meses_activos as (
select *,
case
  when transacciones >= 2 then 1 
  else 0 
  end  as  activo
  from tx_mensual
),
secuencias as (
select
cliente_sk,
nombre,
mes,
activo,
lag(activo,1) OVER(partition by cliente_sk order by mes) as m1,
lag(activo,2) OVER(partition by cliente_sk order by mes) as m2
from meses_activos
),
clientes_fieles as (
select * 
from
secuencias 
where activo = 1 and m1=1 and m2 = 1
),
churn_flag as ( 
select 
cf.cliente_sk,
cf.nombre,
cf.mes,
lead(ma.activo,1) OVER(partition by cf.cliente_sk order by cf.mes) as siguiente_mes
from clientes_fieles as cf
inner join meses_activos as ma on cf.cliente_sk=ma.cliente_sk and 
cf.mes=ma.mes
)
select * from churn_flag where siguiente_mes = 0 or siguiente_mes is null;

--Clientes Recuperados: reactivacion tras periodos de inactividad 
with movimientos as ( 
select 
ft.cliente_sk,
dc.nombre_canal,
dt.fecha,
lag(dt.fecha) over (partition by cliente_sk order by dt.fecha) as ultima_transaccion
from fact.transacciones as ft
inner join dim.tiempo as dt on ft.tiempo_sk=dt.tiempo_sk
inner join dim.canal as dc on ft.canal_sk=dc.canal_sk
where ft.estado_transaccion='Exitosa'
)
select
cliente_sk,
nombre_canal,
fecha as fecha_reactivacion,
ultima_transaccion,
DATEDIFF(day,ultima_transaccion,fecha) as dias_inactivo
from movimientos
where DATEDIFF(day,ultima_transaccion,fecha) >=90

--Frecuencia de uso por canal
with transacciones_canal as (
select
dcl.nombre_canal canal,
dc.segmento_cliente,
count(*) transacciones 
from fact.transacciones as ft
inner join dim.canal as dcl on ft.canal_sk=dcl.canal_sk
inner join dim.cliente as dc on ft.cliente_sk=dc.cliente_sk
where ft.estado_transaccion='Exitosa'
group by dcl.nombre_canal,dc.segmento_cliente
),
pct_transacciones_canal as (
select
canal,
segmento_cliente,
transacciones,
sum(transacciones) OVER() as total_transacciones
from transacciones_canal
group by canal,transacciones,segmento_cliente
)
select
segmento_cliente,
canal,
transacciones,
format(transacciones *100.0 / total_transacciones,'N2','es-ES') as pct_uso
from pct_transacciones_canal
order by pct_uso desc;

--Clientes con prestamo activo y baja actividad transaccional 
with snapshots_reciente as (
select *, 
ROW_NUMBER() OVER (
partition by prestamo_id order by tiempo_sk
) as rn
from fact.prestamos
where fue_castigado = 0 and nro_cuotas_pagadas < nro_cuotas_total
),
prestamos_vigentes as (
select
cliente_sk,prestamo_id,dpd,estado_sk
from snapshots_reciente 
where rn=1
),
actividad_reciente as (
 SELECT
        ft.cliente_sk,
        COUNT(*) AS total_transacciones
    FROM fact.transacciones AS ft
    INNER JOIN dim.tiempo AS dt ON ft.tiempo_sk = dt.tiempo_sk
    WHERE ft.estado_transaccion = 'Exitosa'
      AND dt.fecha >= DATEADD(DAY, -60, (SELECT MAX(fecha) FROM dim.tiempo))
    GROUP BY ft.cliente_sk
)
select
vp.cliente_sk,
vp.prestamo_id,
vp.dpd,
vp.estado_sk,
ar.total_transacciones
from prestamos_vigentes as vp
inner join actividad_reciente as ar on vp.cliente_sk=ar.cliente_sk
where total_transacciones <2
order by vp.cliente_sk

--Crecimiento MoM del Volumen Transaccional
with base_volumen as (
select
dt.anio,
dt.mes,
sum(ft.monto_sol) as monto_total
from fact.transacciones as ft
inner join dim.tiempo as dt on ft.tiempo_sk=dt.tiempo_sk
group by dt.anio,dt.mes
),
tendencia_mom as (
select 
anio,
mes,
monto_total,
lag(monto_total) OVER( order by anio,mes) monto_anterior,
((monto_total - lag(monto_total) OVER(order by anio,mes)) / lag(monto_total) OVER(order by anio,mes)) *100 as pct_mom
from base_volumen
)
select
anio as año,
mes,
monto_anterior as monto_año_anterior,
monto_total,
format(pct_mom,'N2','es-ES') as pct_mom
from tendencia_mom
order by anio,mes

--Rolling average de 3 meses sobre monto desembolsado
with desembolso_total as (
select
dt.anio,
dt.mes,
sum(fp.monto_desembolsado_sol) as total_monto
from fact.prestamos as fp
inner join dim.tiempo as dt on fp.tiempo_desembolso_sk=dt.tiempo_sk
group by dt.anio,dt.mes
),
media_movil as (
select
anio,
mes,
total_monto,
avg(total_monto) OVER(order by anio,mes ROWS BETWEEN 2 PRECEDING and CURRENT ROW) as rolling_average_3m
from desembolso_total
)
select
anio as año,
mes,
total_monto,
rolling_average_3m,
case
  when total_monto > rolling_average_3m then 'Por encima de tendencia'
  when total_monto < rolling_average_3m then 'Por debajo de tendencia'
  else 'En linea con tendencia'
  end as posicion_vs_Tendencia
from media_movil
order by año,mes

--Estacionalidad transacciones en quincenas vs resto del mes
with total_quincena as (
select
dt.anio,
dt.mes,
sum(ft.monto_sol)  /  count(*) as promedio_monto_quincenal,
count(*) as volumen_total_quincenal
from fact.transacciones as ft
inner join dim.tiempo as dt on ft.tiempo_sk=dt.tiempo_sk
where ft.estado_transaccion='Exitosa' and dt.es_quincena=1
group by dt.anio,dt.mes
),
total_resto as(
select
dt.anio,
dt.mes,
sum(ft.monto_sol)  /  count(*) as promedio_monto_restante,
count(*) as volumen_total_restante
from fact.transacciones as ft
inner join dim.tiempo as dt on ft.tiempo_sk=dt.tiempo_sk
where ft.estado_transaccion='Exitosa' and dt.es_quincena=0
group by dt.anio,dt.mes
)
select
coalesce(t.anio,tr.anio) as año,
coalesce(t.mes,tr.mes) as mes,
t.promedio_monto_quincenal,
t.volumen_total_quincenal,
tr.promedio_monto_restante,
tr.volumen_total_restante
from total_quincena as t
full outer join total_resto as tr on t.anio = tr.anio and t.mes = tr.mes
order by t.anio,t.mes asc


-- Tendencia de nuevos clientes registrados por mes 
with total_nuevos_clientes as ( 
select
dt.anio,
dt.mes,
count(dc.cliente_id) as total_clientes_nuevos
from dim.cliente as dc
inner join dim.tiempo as dt on dc.fecha_registro = dt.fecha
group by dt.anio,dt.mes
),
total_acumulado as (
select
anio,
mes,
total_clientes_nuevos,
sum(total_clientes_nuevos) OVER(ORDER BY anio,mes ROWS UNBOUNDED PRECEDING) as total_acumulado
from total_nuevos_clientes
)
select
anio as año,
mes,
total_clientes_nuevos,
total_acumulado
from total_acumulado
order by año,mes

--Comparativa Trimestral de Morosidad = 
With saldo_mora_saldo_capital as (
select
dt.anio,
dt.trimestre,
sum(fp.saldo_mora_sol) as total_mora,
sum(fp.saldo_capital_sol) as total_capital 
from fact.prestamos as fp
inner join dim.tiempo as dt on fp.tiempo_sk=dt.tiempo_sk
group by dt.anio,dt.trimestre
),
variacion_morosidad as (
select 
anio,
trimestre,
total_mora,
total_capital,
((total_mora - lag(total_mora) OVER(Partition by anio order by trimestre)) / lag(total_mora) OVER(Partition by anio order by trimestre)) * 100 as variacion_trimestral 
from saldo_mora_saldo_capital 
)
select
anio as año,
trimestre,
total_mora,
Format(total_capital,'N2','es-ES') as total_capital,
Format(variacion_trimestral,'N2','es-ES') as variacion_trimestral
from variacion_morosidad
order by año,trimestre

--Ranking de distritos por volumen transaccionado con tendencia
with volumen_transaccionado as ( 
select
dt.anio,
dc.distrito,
sum(ft.monto_sol) as volumen_total
from fact.transacciones as ft 
inner join dim.tiempo as dt on ft.tiempo_sk=dt.tiempo_sk
inner join dim.cliente as dc on ft.cliente_sk=dc.cliente_sk
group by dt.anio,dc.distrito
)
select
anio as año,
distrito,
volumen_total,
RANK() OVER(Partition by anio order by volumen_total desc) as rank_distrito_volumen
from volumen_transaccionado
order by año
