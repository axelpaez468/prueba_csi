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

echo "[init] Esperando a que SQL Server acepte conexiones..."
for _ in $(seq 1 60); do
  if sql_sa -Q "SELECT 1" -o /dev/null 2>/dev/null; then break; fi
  sleep 2
done

echo "[init] Aplicando esquema y datos semilla..."
sql_sa -I -f 65001 -i /db/init/init.sql \
  -v DB_NAME="$DB_NAME" APP_DB_USER="$APP_DB_USER" APP_DB_PASSWORD="$APP_DB_PASSWORD"

touch /tmp/init-done
echo "[init] Listo."
wait "$pid"
