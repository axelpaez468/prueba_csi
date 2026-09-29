#!/bin/bash
# Arranca SQL Server, espera a que acepte conexiones y aplica db/init/init.sql.
# El script es idempotente, así que se ejecuta en cada arranque sin duplicar datos.
set -euo pipefail

rm -f /tmp/init-done
source /db/sqlcmd.sh

/opt/mssql/bin/sqlservr &
pid=$!
# Reenvía el apagado de "docker stop" a SQL Server para que cierre limpio.
trap 'kill -TERM "$pid"; wait "$pid"' TERM INT

# En un reinicio, SQL Server acepta conexiones antes de terminar de poner en línea las bases
# existentes; ejecutar init.sql en ese momento falla con "cannot be autostarted during startup".
# Por eso se espera a que la base no exista todavía o esté ONLINE.
LISTA="SET NOCOUNT ON; SELECT CASE WHEN DB_ID('$DB_NAME') IS NULL OR DATABASEPROPERTYEX('$DB_NAME','Status') = 'ONLINE' THEN 1 ELSE 0 END"

echo "[init] Esperando a que SQL Server y la base '$DB_NAME' estén listos..."
for _ in $(seq 1 90); do
  if [ "$(sql_sa -h -1 -Q "$LISTA" 2>/dev/null | tr -d '[:space:]')" = "1" ]; then break; fi
  sleep 2
done

echo "[init] Aplicando esquema y datos semilla..."
for intento in 1 2 3 4 5; do
  if sql_sa -I -f 65001 -i /db/init/init.sql \
      -v DB_NAME="$DB_NAME" APP_DB_USER="$APP_DB_USER" APP_DB_PASSWORD="$APP_DB_PASSWORD"; then
    touch /tmp/init-done
    echo "[init] Listo."
    break
  fi
  echo "[init] Falló el intento $intento; reintentando en 5 s..."
  sleep 5
done

if [ ! -f /tmp/init-done ]; then
  echo "[init] No se pudo inicializar la base de datos." >&2
  kill -TERM "$pid"
  exit 1
fi

wait "$pid"
