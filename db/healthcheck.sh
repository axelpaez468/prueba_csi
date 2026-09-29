#!/bin/bash
# Sana = el script de inicialización terminó y la tabla de productos responde.
set -euo pipefail
test -f /tmp/init-done
source /db/sqlcmd.sh
sql_sa -Q "SET NOCOUNT ON; SELECT TOP 1 1 FROM [$DB_NAME].dbo.Productos" -o /dev/null
