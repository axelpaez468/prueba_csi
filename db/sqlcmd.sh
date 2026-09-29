#!/bin/bash
# Ubica sqlcmd dentro de la imagen de SQL Server (mssql-tools18 en versiones recientes).
if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=(/opt/mssql-tools18/bin/sqlcmd -C)   # -C: confía en el certificado autofirmado local
else
  SQLCMD=(/opt/mssql-tools/bin/sqlcmd)
fi

sql_sa() {
  "${SQLCMD[@]}" -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -b "$@"
}
