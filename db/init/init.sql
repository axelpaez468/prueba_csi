-- =====================================================================
-- Esquema y datos semilla del Sistema de Pedidos.
-- Idempotente: se puede ejecutar varias veces sin duplicar datos.
--
-- Variables de sqlcmd (se pasan con -v desde docker-compose):
--   DB_NAME           nombre de la base de datos
--   APP_DB_USER       login con permisos mínimos que usa la API
--   APP_DB_PASSWORD   contraseña de ese login (viene del .env, nunca del repo)
-- =====================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_ID(N'$(DB_NAME)') IS NULL
    CREATE DATABASE [$(DB_NAME)];
GO

USE [$(DB_NAME)];
GO

-- ---------- Tablas ----------
IF OBJECT_ID(N'dbo.Usuarios', N'U') IS NULL
CREATE TABLE dbo.Usuarios (
    Id           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Usuarios PRIMARY KEY,
    Username     NVARCHAR(50)      NOT NULL CONSTRAINT UQ_Usuarios_Username UNIQUE,
    PasswordHash NVARCHAR(100)     NOT NULL,
    Rol          NVARCHAR(20)      NOT NULL CONSTRAINT CK_Usuarios_Rol CHECK (Rol IN (N'VENDEDOR', N'ADMIN'))
);
GO

IF OBJECT_ID(N'dbo.Productos', N'U') IS NULL
CREATE TABLE dbo.Productos (
    Id     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Productos PRIMARY KEY,
    Codigo NVARCHAR(20)      NOT NULL CONSTRAINT UQ_Productos_Codigo UNIQUE,
    Nombre NVARCHAR(100)     NOT NULL,
    Precio DECIMAL(18,2)     NOT NULL CONSTRAINT CK_Productos_Precio CHECK (Precio >= 0),
    -- Última barrera: aunque falle la lógica de la API, la BD nunca acepta stock negativo.
    Stock  INT               NOT NULL CONSTRAINT CK_Productos_Stock CHECK (Stock >= 0)
);
GO

IF OBJECT_ID(N'dbo.Pedidos', N'U') IS NULL
CREATE TABLE dbo.Pedidos (
    Id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Pedidos PRIMARY KEY,
    UsuarioId INT               NOT NULL CONSTRAINT FK_Pedidos_Usuarios REFERENCES dbo.Usuarios(Id),
    Fecha     DATETIME2         NOT NULL,
    Total     DECIMAL(18,2)     NOT NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Pedidos_UsuarioId')
    CREATE INDEX IX_Pedidos_UsuarioId ON dbo.Pedidos(UsuarioId);
GO

IF OBJECT_ID(N'dbo.PedidoDetalle', N'U') IS NULL
CREATE TABLE dbo.PedidoDetalle (
    PedidoId       INT           NOT NULL CONSTRAINT FK_PedidoDetalle_Pedidos REFERENCES dbo.Pedidos(Id) ON DELETE CASCADE,
    ProductoId     INT           NOT NULL CONSTRAINT FK_PedidoDetalle_Productos REFERENCES dbo.Productos(Id),
    Cantidad       INT           NOT NULL CONSTRAINT CK_PedidoDetalle_Cantidad CHECK (Cantidad > 0),
    PrecioUnitario DECIMAL(18,2) NOT NULL,
    Subtotal       DECIMAL(18,2) NOT NULL,
    -- La PK compuesta impide también a nivel de BD un producto repetido en el mismo pedido.
    CONSTRAINT PK_PedidoDetalle PRIMARY KEY (PedidoId, ProductoId)
);
GO

-- =====================================================================
-- Login de ERP: correo, 2FA con app autenticadora, recuperación de contraseña y bitácora.
-- Migración incremental e idempotente: en una BD nueva agrega las columnas justo después de crear la
-- tabla; en una BD existente las agrega sin perder datos.
-- =====================================================================
IF COL_LENGTH(N'dbo.Usuarios', N'Email') IS NULL
    ALTER TABLE dbo.Usuarios ADD Email NVARCHAR(254) NULL;
IF COL_LENGTH(N'dbo.Usuarios', N'Telefono') IS NULL
    ALTER TABLE dbo.Usuarios ADD Telefono NVARCHAR(20) NULL;
IF COL_LENGTH(N'dbo.Usuarios', N'DosFactor') IS NULL
    ALTER TABLE dbo.Usuarios ADD DosFactor NVARCHAR(10) NOT NULL
        CONSTRAINT DF_Usuarios_DosFactor DEFAULT (N'NINGUNO')
        CONSTRAINT CK_Usuarios_DosFactor CHECK (DosFactor IN (N'NINGUNO', N'TOTP'));
IF COL_LENGTH(N'dbo.Usuarios', N'TotpSecretoCifrado') IS NULL
    ALTER TABLE dbo.Usuarios ADD TotpSecretoCifrado NVARCHAR(200) NULL;   -- AES-GCM, nunca en claro
IF COL_LENGTH(N'dbo.Usuarios', N'TotpUltimoPaso') IS NULL
    ALTER TABLE dbo.Usuarios ADD TotpUltimoPaso BIGINT NULL;              -- anti-reutilización de códigos
IF COL_LENGTH(N'dbo.Usuarios', N'TotpPendienteCifrado') IS NULL
    ALTER TABLE dbo.Usuarios ADD TotpPendienteCifrado NVARCHAR(200) NULL;
IF COL_LENGTH(N'dbo.Usuarios', N'VersionSesion') IS NULL
    ALTER TABLE dbo.Usuarios ADD VersionSesion INT NOT NULL CONSTRAINT DF_Usuarios_VersionSesion DEFAULT (0);
GO

-- BD existente con los usuarios originales: se les asigna correo, y el admin recibe su nueva contraseña.
UPDATE dbo.Usuarios SET Email = LOWER(Username) + N'@pedidos.local' WHERE Email IS NULL;
UPDATE dbo.Usuarios
   SET PasswordHash = N'$2a$11$E6LutlNGkp4N/dpe38.jW.ZfVU6YeW/D4mgxag/fpqIMZWisZA4FW',
       Telefono = N'+50255550101', VersionSesion = VersionSesion + 1
 WHERE Username = N'admin' AND DosFactor = N'NINGUNO' AND Telefono IS NULL;
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.Usuarios') AND name = N'Email' AND is_nullable = 1)
    ALTER TABLE dbo.Usuarios ALTER COLUMN Email NVARCHAR(254) NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Usuarios_Email')
    CREATE UNIQUE INDEX UQ_Usuarios_Email ON dbo.Usuarios(Email);
GO

IF OBJECT_ID(N'dbo.CodigosRespaldo', N'U') IS NULL
CREATE TABLE dbo.CodigosRespaldo (
    Id         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CodigosRespaldo PRIMARY KEY,
    UsuarioId  INT       NOT NULL CONSTRAINT FK_CodigosRespaldo_Usuarios REFERENCES dbo.Usuarios(Id) ON DELETE CASCADE,
    CodigoHash CHAR(64)  NOT NULL,   -- HMAC-SHA256: el código en claro solo lo ve el usuario una vez
    UsadoEn    DATETIME2 NULL,
    INDEX IX_CodigosRespaldo_UsuarioId (UsuarioId)
);
GO

IF OBJECT_ID(N'dbo.TokensRecuperacion', N'U') IS NULL
CREATE TABLE dbo.TokensRecuperacion (
    Id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TokensRecuperacion PRIMARY KEY,
    UsuarioId INT       NOT NULL CONSTRAINT FK_TokensRecuperacion_Usuarios REFERENCES dbo.Usuarios(Id) ON DELETE CASCADE,
    TokenHash CHAR(64)  NOT NULL CONSTRAINT UQ_TokensRecuperacion_TokenHash UNIQUE,
    ExpiraEn  DATETIME2 NOT NULL,
    UsadoEn   DATETIME2 NULL,
    CreadoEn  DATETIME2 NOT NULL
);
GO

IF OBJECT_ID(N'dbo.DispositivosConfiables', N'U') IS NULL
CREATE TABLE dbo.DispositivosConfiables (
    Id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DispositivosConfiables PRIMARY KEY,
    UsuarioId INT       NOT NULL CONSTRAINT FK_DispositivosConfiables_Usuarios REFERENCES dbo.Usuarios(Id) ON DELETE CASCADE,
    TokenHash CHAR(64)  NOT NULL CONSTRAINT UQ_DispositivosConfiables_TokenHash UNIQUE,
    ExpiraEn  DATETIME2 NOT NULL,
    CreadoEn  DATETIME2 NOT NULL
);
GO

IF OBJECT_ID(N'dbo.DispositivosConocidos', N'U') IS NULL
CREATE TABLE dbo.DispositivosConocidos (
    Id           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DispositivosConocidos PRIMARY KEY,
    UsuarioId    INT       NOT NULL CONSTRAINT FK_DispositivosConocidos_Usuarios REFERENCES dbo.Usuarios(Id) ON DELETE CASCADE,
    Huella       CHAR(64)  NOT NULL,
    PrimerAcceso DATETIME2 NOT NULL,
    UltimoAcceso DATETIME2 NOT NULL,
    CONSTRAINT UQ_DispositivosConocidos UNIQUE (UsuarioId, Huella)
);
GO

-- Bitácora de auditoría. Sin FK a Usuarios: también registra intentos con correos inexistentes.
IF OBJECT_ID(N'dbo.BitacoraAccesos', N'U') IS NULL
CREATE TABLE dbo.BitacoraAccesos (
    Id        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BitacoraAccesos PRIMARY KEY,
    UsuarioId INT           NULL,
    Email     NVARCHAR(254) NOT NULL,
    Evento    NVARCHAR(40)  NOT NULL,
    Exito     BIT           NOT NULL,
    Ip        NVARCHAR(45)  NULL,
    UserAgent NVARCHAR(300) NULL,
    Detalle   NVARCHAR(300) NULL,
    Fecha     DATETIME2     NOT NULL,
    INDEX IX_BitacoraAccesos_Fecha (Fecha),
    INDEX IX_BitacoraAccesos_UsuarioId (UsuarioId)
);
GO

-- =====================================================================
-- Administración de usuarios: nombre, apellido, código corporativo, estado activo/inactivo.
-- =====================================================================
IF COL_LENGTH(N'dbo.Usuarios', N'Nombre') IS NULL
    ALTER TABLE dbo.Usuarios ADD Nombre NVARCHAR(60) NULL;
IF COL_LENGTH(N'dbo.Usuarios', N'Apellido') IS NULL
    ALTER TABLE dbo.Usuarios ADD Apellido NVARCHAR(60) NULL;
IF COL_LENGTH(N'dbo.Usuarios', N'CodigoCorporativo') IS NULL
    ALTER TABLE dbo.Usuarios ADD CodigoCorporativo NVARCHAR(20) NULL;
IF COL_LENGTH(N'dbo.Usuarios', N'Activo') IS NULL
    ALTER TABLE dbo.Usuarios ADD Activo BIT NOT NULL CONSTRAINT DF_Usuarios_Activo DEFAULT (1);
IF COL_LENGTH(N'dbo.Usuarios', N'CreadoEn') IS NULL
    ALTER TABLE dbo.Usuarios ADD CreadoEn DATETIME2 NOT NULL CONSTRAINT DF_Usuarios_CreadoEn DEFAULT (SYSUTCDATETIME());
GO

-- Username pasa a ser el nombre para mostrar ("Nombre Apellido"): puede repetirse y es más largo.
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'UQ_Usuarios_Username')
    ALTER TABLE dbo.Usuarios DROP CONSTRAINT UQ_Usuarios_Username;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.Usuarios') AND name = N'Username' AND max_length < 260)
    ALTER TABLE dbo.Usuarios ALTER COLUMN Username NVARCHAR(130) NOT NULL;
GO

-- BD existente: datos para los usuarios originales.
UPDATE dbo.Usuarios SET Nombre = N'Vendedor', Apellido = N'Demo', CodigoCorporativo = N'VEN-0001',
       Telefono = COALESCE(Telefono, N'+50255550102'), Username = N'Vendedor Demo'
 WHERE Nombre IS NULL AND Rol = N'VENDEDOR' AND Username = N'vendedor';
UPDATE dbo.Usuarios SET Nombre = N'Administrador', Apellido = N'General', CodigoCorporativo = N'ADM-0001',
       Username = N'Administrador General'
 WHERE Nombre IS NULL AND Rol = N'ADMIN' AND Username = N'admin';
-- Cualquier otro usuario previo: valores derivados para cumplir las restricciones.
UPDATE dbo.Usuarios SET Nombre = Username, Apellido = N'-', CodigoCorporativo = CONCAT(N'USR-', RIGHT(CONCAT(N'0000', Id), 4))
 WHERE Nombre IS NULL;
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.Usuarios') AND name = N'Nombre' AND is_nullable = 1)
BEGIN
    ALTER TABLE dbo.Usuarios ALTER COLUMN Nombre NVARCHAR(60) NOT NULL;
    ALTER TABLE dbo.Usuarios ALTER COLUMN Apellido NVARCHAR(60) NOT NULL;
    ALTER TABLE dbo.Usuarios ALTER COLUMN CodigoCorporativo NVARCHAR(20) NOT NULL;
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Usuarios_CodigoCorporativo')
    CREATE UNIQUE INDEX UQ_Usuarios_CodigoCorporativo ON dbo.Usuarios(CodigoCorporativo);
GO

-- =====================================================================
-- Se retira el 2FA por SMS: solo app autenticadora (Google Authenticator).
-- Quien usaba SMS queda sin 2FA; los administradores deberán configurar la app en su próximo ingreso.
-- =====================================================================
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Usuarios_DosFactor' AND definition LIKE N'%SMS%')
BEGIN
    UPDATE dbo.Usuarios SET DosFactor = N'NINGUNO', VersionSesion = VersionSesion + 1 WHERE DosFactor = N'SMS';
    ALTER TABLE dbo.Usuarios DROP CONSTRAINT CK_Usuarios_DosFactor;
    ALTER TABLE dbo.Usuarios ADD CONSTRAINT CK_Usuarios_DosFactor CHECK (DosFactor IN (N'NINGUNO', N'TOTP'));
END
GO
IF COL_LENGTH(N'dbo.Usuarios', N'TelefonoPendiente') IS NOT NULL
    ALTER TABLE dbo.Usuarios DROP COLUMN TelefonoPendiente;
IF OBJECT_ID(N'dbo.CodigosVerificacion', N'U') IS NOT NULL
    DROP TABLE dbo.CodigosVerificacion;
GO

-- =====================================================================
-- ERP: ventas con cliente y factura, inventario con kardex y costo promedio, compras y contabilidad.
-- =====================================================================

-- Roles nuevos: BODEGA, COMPRAS y CONTADOR.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Usuarios_Rol' AND definition NOT LIKE N'%BODEGA%')
BEGIN
    ALTER TABLE dbo.Usuarios DROP CONSTRAINT CK_Usuarios_Rol;
    ALTER TABLE dbo.Usuarios ADD CONSTRAINT CK_Usuarios_Rol
        CHECK (Rol IN (N'VENDEDOR', N'ADMIN', N'BODEGA', N'COMPRAS', N'CONTADOR'));
END
GO

-- Productos: costo promedio (sin IVA), stock mínimo y baja lógica.
IF COL_LENGTH(N'dbo.Productos', N'CostoPromedio') IS NULL
    ALTER TABLE dbo.Productos ADD CostoPromedio DECIMAL(18,4) NOT NULL
        CONSTRAINT DF_Productos_CostoPromedio DEFAULT (0)
        CONSTRAINT CK_Productos_Costo CHECK (CostoPromedio >= 0);
IF COL_LENGTH(N'dbo.Productos', N'StockMinimo') IS NULL
    ALTER TABLE dbo.Productos ADD StockMinimo INT NOT NULL
        CONSTRAINT DF_Productos_StockMinimo DEFAULT (0)
        CONSTRAINT CK_Productos_StockMinimo CHECK (StockMinimo >= 0);
IF COL_LENGTH(N'dbo.Productos', N'Activo') IS NULL
    ALTER TABLE dbo.Productos ADD Activo BIT NOT NULL CONSTRAINT DF_Productos_Activo DEFAULT (1);
GO

-- Ficha del producto: marca, categoría, descripción detallada, garantía y especificaciones (JSON).
IF COL_LENGTH(N'dbo.Productos', N'Marca') IS NULL
    ALTER TABLE dbo.Productos ADD Marca NVARCHAR(60) NULL;
IF COL_LENGTH(N'dbo.Productos', N'Categoria') IS NULL
    ALTER TABLE dbo.Productos ADD Categoria NVARCHAR(60) NULL;
IF COL_LENGTH(N'dbo.Productos', N'Descripcion') IS NULL
    ALTER TABLE dbo.Productos ADD Descripcion NVARCHAR(2000) NULL;
IF COL_LENGTH(N'dbo.Productos', N'GarantiaMeses') IS NULL
    ALTER TABLE dbo.Productos ADD GarantiaMeses INT NOT NULL CONSTRAINT DF_Productos_GarantiaMeses DEFAULT (0)
        CONSTRAINT CK_Productos_Garantia CHECK (GarantiaMeses BETWEEN 0 AND 120);
IF COL_LENGTH(N'dbo.Productos', N'Especificaciones') IS NULL
    ALTER TABLE dbo.Productos ADD Especificaciones NVARCHAR(4000) NOT NULL CONSTRAINT DF_Productos_Especificaciones DEFAULT (N'[]')
        CONSTRAINT CK_Productos_Especificaciones CHECK (ISJSON(Especificaciones) = 1);
GO

IF OBJECT_ID(N'dbo.Clientes', N'U') IS NULL
CREATE TABLE dbo.Clientes (
    Id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Clientes PRIMARY KEY,
    Nit       NVARCHAR(15)  NOT NULL CONSTRAINT UQ_Clientes_Nit UNIQUE,   -- sin guion; "CF" = consumidor final
    Nombre    NVARCHAR(150) NOT NULL,
    Direccion NVARCHAR(200) NULL,
    Telefono  NVARCHAR(20)  NULL,
    Email     NVARCHAR(254) NULL,
    Activo    BIT           NOT NULL CONSTRAINT DF_Clientes_Activo DEFAULT (1),
    CreadoEn  DATETIME2     NOT NULL CONSTRAINT DF_Clientes_CreadoEn DEFAULT (SYSUTCDATETIME())
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.Clientes WHERE Nit = N'CF')
    INSERT INTO dbo.Clientes (Nit, Nombre, Direccion) VALUES (N'CF', N'Consumidor Final', N'Ciudad');
GO

IF OBJECT_ID(N'dbo.Proveedores', N'U') IS NULL
CREATE TABLE dbo.Proveedores (
    Id        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Proveedores PRIMARY KEY,
    Nit       NVARCHAR(15)  NOT NULL CONSTRAINT UQ_Proveedores_Nit UNIQUE,
    Nombre    NVARCHAR(150) NOT NULL,
    Contacto  NVARCHAR(100) NULL,
    Telefono  NVARCHAR(20)  NULL,
    Email     NVARCHAR(254) NULL,
    Direccion NVARCHAR(200) NULL,
    Activo    BIT           NOT NULL CONSTRAINT DF_Proveedores_Activo DEFAULT (1),
    CreadoEn  DATETIME2     NOT NULL CONSTRAINT DF_Proveedores_CreadoEn DEFAULT (SYSUTCDATETIME())
);
GO

-- Pedidos = ventas de contado con factura (simulación FEL). Precios con IVA incluido.
IF COL_LENGTH(N'dbo.Pedidos', N'ClienteId') IS NULL
    ALTER TABLE dbo.Pedidos ADD ClienteId INT NULL;
IF COL_LENGTH(N'dbo.Pedidos', N'FormaPago') IS NULL
    ALTER TABLE dbo.Pedidos ADD FormaPago NVARCHAR(15) NOT NULL CONSTRAINT DF_Pedidos_FormaPago DEFAULT (N'EFECTIVO')
        CONSTRAINT CK_Pedidos_FormaPago CHECK (FormaPago IN (N'EFECTIVO', N'TARJETA', N'TRANSFERENCIA'));
IF COL_LENGTH(N'dbo.Pedidos', N'BaseImponible') IS NULL
    ALTER TABLE dbo.Pedidos ADD BaseImponible DECIMAL(18,2) NOT NULL CONSTRAINT DF_Pedidos_BaseImponible DEFAULT (0);
IF COL_LENGTH(N'dbo.Pedidos', N'Iva') IS NULL
    ALTER TABLE dbo.Pedidos ADD Iva DECIMAL(18,2) NOT NULL CONSTRAINT DF_Pedidos_Iva DEFAULT (0);
IF COL_LENGTH(N'dbo.Pedidos', N'Costo') IS NULL
    ALTER TABLE dbo.Pedidos ADD Costo DECIMAL(18,2) NOT NULL CONSTRAINT DF_Pedidos_Costo DEFAULT (0);
IF COL_LENGTH(N'dbo.Pedidos', N'Autorizacion') IS NULL
    ALTER TABLE dbo.Pedidos ADD Autorizacion UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Pedidos_Autorizacion DEFAULT (NEWID());
IF COL_LENGTH(N'dbo.PedidoDetalle', N'CostoUnitario') IS NULL
    ALTER TABLE dbo.PedidoDetalle ADD CostoUnitario DECIMAL(18,4) NOT NULL CONSTRAINT DF_PedidoDetalle_CostoUnitario DEFAULT (0);
GO

-- Pedidos anteriores al ERP: a consumidor final, con el IVA separado del total.
UPDATE dbo.Pedidos SET ClienteId = (SELECT Id FROM dbo.Clientes WHERE Nit = N'CF') WHERE ClienteId IS NULL;
UPDATE dbo.Pedidos SET BaseImponible = ROUND(Total / 1.12, 2), Iva = Total - ROUND(Total / 1.12, 2)
 WHERE BaseImponible = 0 AND Total > 0;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.Pedidos') AND name = N'ClienteId' AND is_nullable = 1)
    ALTER TABLE dbo.Pedidos ALTER COLUMN ClienteId INT NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Pedidos_Clientes')
    ALTER TABLE dbo.Pedidos ADD CONSTRAINT FK_Pedidos_Clientes FOREIGN KEY (ClienteId) REFERENCES dbo.Clientes(Id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Pedidos_ClienteId')
    CREATE INDEX IX_Pedidos_ClienteId ON dbo.Pedidos(ClienteId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Pedidos_Fecha')
    CREATE INDEX IX_Pedidos_Fecha ON dbo.Pedidos(Fecha);
GO

-- Kardex: nunca se edita ni se borra.
IF OBJECT_ID(N'dbo.MovimientosInventario', N'U') IS NULL
CREATE TABLE dbo.MovimientosInventario (
    Id            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MovimientosInventario PRIMARY KEY,
    ProductoId    INT           NOT NULL CONSTRAINT FK_Movimientos_Productos REFERENCES dbo.Productos(Id),
    Fecha         DATETIME2     NOT NULL,
    Tipo          NVARCHAR(20)  NOT NULL CONSTRAINT CK_Movimientos_Tipo
                  CHECK (Tipo IN (N'INICIAL', N'VENTA', N'COMPRA', N'AJUSTE_ENTRADA', N'AJUSTE_SALIDA')),
    Cantidad      INT           NOT NULL,      -- positiva: entrada; negativa: salida
    CostoUnitario DECIMAL(18,4) NOT NULL,
    Saldo         INT           NOT NULL CONSTRAINT CK_Movimientos_Saldo CHECK (Saldo >= 0),
    CostoPromedio DECIMAL(18,4) NOT NULL,
    Referencia    NVARCHAR(120) NOT NULL,
    UsuarioId     INT           NULL CONSTRAINT FK_Movimientos_Usuarios REFERENCES dbo.Usuarios(Id),
    INDEX IX_Movimientos_Producto (ProductoId, Id)
);
GO

IF OBJECT_ID(N'dbo.OrdenesCompra', N'U') IS NULL
CREATE TABLE dbo.OrdenesCompra (
    Id               INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrdenesCompra PRIMARY KEY,
    ProveedorId      INT           NOT NULL CONSTRAINT FK_OrdenesCompra_Proveedores REFERENCES dbo.Proveedores(Id),
    Fecha            DATETIME2     NOT NULL,
    Estado           NVARCHAR(10)  NOT NULL CONSTRAINT CK_OrdenesCompra_Estado CHECK (Estado IN (N'PENDIENTE', N'RECIBIDA', N'ANULADA')),
    Subtotal         DECIMAL(18,2) NOT NULL,   -- sin IVA
    Iva              DECIMAL(18,2) NOT NULL,
    Total            DECIMAL(18,2) NOT NULL,
    Observaciones    NVARCHAR(300) NULL,
    UsuarioId        INT           NOT NULL CONSTRAINT FK_OrdenesCompra_Usuarios REFERENCES dbo.Usuarios(Id),
    FechaRecepcion   DATETIME2     NULL,
    RecibidaPorId    INT           NULL CONSTRAINT FK_OrdenesCompra_RecibidaPor REFERENCES dbo.Usuarios(Id),
    FacturaProveedor NVARCHAR(40)  NULL,
    INDEX IX_OrdenesCompra_Estado (Estado)
);
GO

IF OBJECT_ID(N'dbo.OrdenCompraDetalle', N'U') IS NULL
CREATE TABLE dbo.OrdenCompraDetalle (
    OrdenCompraId INT           NOT NULL CONSTRAINT FK_OrdenCompraDetalle_Ordenes REFERENCES dbo.OrdenesCompra(Id) ON DELETE CASCADE,
    ProductoId    INT           NOT NULL CONSTRAINT FK_OrdenCompraDetalle_Productos REFERENCES dbo.Productos(Id),
    Cantidad      INT           NOT NULL CONSTRAINT CK_OrdenCompraDetalle_Cantidad CHECK (Cantidad > 0),
    CostoUnitario DECIMAL(18,2) NOT NULL CONSTRAINT CK_OrdenCompraDetalle_Costo CHECK (CostoUnitario > 0),
    Subtotal      DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_OrdenCompraDetalle PRIMARY KEY (OrdenCompraId, ProductoId)
);
GO

-- Contabilidad: el primer dígito del código define el tipo de cuenta.
IF OBJECT_ID(N'dbo.CuentasContables', N'U') IS NULL
CREATE TABLE dbo.CuentasContables (
    Id     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CuentasContables PRIMARY KEY,
    Codigo NVARCHAR(10)  NOT NULL CONSTRAINT UQ_CuentasContables_Codigo UNIQUE,
    Nombre NVARCHAR(100) NOT NULL,
    Tipo   NVARCHAR(10)  NOT NULL CONSTRAINT CK_Cuentas_Tipo
           CHECK (Tipo IN (N'ACTIVO', N'PASIVO', N'CAPITAL', N'INGRESO', N'COSTO', N'GASTO')),
    Activa BIT           NOT NULL CONSTRAINT DF_CuentasContables_Activa DEFAULT (1)
);
GO

IF OBJECT_ID(N'dbo.Partidas', N'U') IS NULL
CREATE TABLE dbo.Partidas (
    Id           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Partidas PRIMARY KEY,
    Fecha        DATE          NOT NULL,      -- fecha contable (hora de Guatemala)
    Concepto     NVARCHAR(200) NOT NULL,
    Origen       NVARCHAR(10)  NOT NULL CONSTRAINT CK_Partidas_Origen
                 CHECK (Origen IN (N'APERTURA', N'VENTA', N'COMPRA', N'AJUSTE', N'MANUAL')),
    ReferenciaId BIGINT        NULL,          -- venta, orden de compra o movimiento que la originó
    UsuarioId    INT           NULL CONSTRAINT FK_Partidas_Usuarios REFERENCES dbo.Usuarios(Id),
    CreadoEn     DATETIME2     NOT NULL,
    Total        DECIMAL(18,2) NOT NULL,
    INDEX IX_Partidas_Fecha (Fecha),
    INDEX IX_Partidas_Origen (Origen, ReferenciaId)
);
GO

IF OBJECT_ID(N'dbo.PartidaDetalle', N'U') IS NULL
CREATE TABLE dbo.PartidaDetalle (
    Id        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PartidaDetalle PRIMARY KEY,
    PartidaId INT           NOT NULL CONSTRAINT FK_PartidaDetalle_Partidas REFERENCES dbo.Partidas(Id) ON DELETE CASCADE,
    CuentaId  INT           NOT NULL CONSTRAINT FK_PartidaDetalle_Cuentas REFERENCES dbo.CuentasContables(Id),
    Debe      DECIMAL(18,2) NOT NULL,
    Haber     DECIMAL(18,2) NOT NULL,
    -- Cada línea va al debe o al haber, nunca a ambos ni con montos negativos.
    CONSTRAINT CK_PartidaDetalle_Montos CHECK (Debe >= 0 AND Haber >= 0 AND ((Debe > 0 AND Haber = 0) OR (Haber > 0 AND Debe = 0))),
    INDEX IX_PartidaDetalle_Cuenta (CuentaId)
);
GO

-- Catálogo de cuentas base (se agregan las que falten).
INSERT INTO dbo.CuentasContables (Codigo, Nombre, Tipo)
SELECT c.Codigo, c.Nombre, c.Tipo
  FROM (VALUES
    (N'1101', N'Caja', N'ACTIVO'),
    (N'1102', N'Bancos', N'ACTIVO'),
    (N'1103', N'Inventario de mercadería', N'ACTIVO'),
    (N'1104', N'IVA por cobrar (crédito fiscal)', N'ACTIVO'),
    (N'2101', N'Proveedores', N'PASIVO'),
    (N'2102', N'IVA por pagar (débito fiscal)', N'PASIVO'),
    (N'3101', N'Capital social', N'CAPITAL'),
    (N'3102', N'Resultados acumulados', N'CAPITAL'),
    (N'4101', N'Ventas', N'INGRESO'),
    (N'4102', N'Otros ingresos', N'INGRESO'),
    (N'5101', N'Costo de ventas', N'COSTO'),
    (N'6101', N'Sueldos y salarios', N'GASTO'),
    (N'6102', N'Alquileres', N'GASTO'),
    (N'6103', N'Energía eléctrica, agua y teléfono', N'GASTO'),
    (N'6104', N'Faltantes y mermas de inventario', N'GASTO'),
    (N'6105', N'Gastos varios', N'GASTO')
  ) AS c (Codigo, Nombre, Tipo)
 WHERE NOT EXISTS (SELECT 1 FROM dbo.CuentasContables x WHERE x.Codigo = c.Codigo);
GO

-- ---------- Datos semilla ----------
-- Hashes BCrypt (work factor 11). Contraseñas de prueba documentadas en el README.
-- Cada usuario configura Google Authenticator en su primer inicio de sesión (el 2FA es obligatorio para todos).
IF NOT EXISTS (SELECT 1 FROM dbo.Usuarios)
INSERT INTO dbo.Usuarios (Username, Nombre, Apellido, CodigoCorporativo, Email, PasswordHash, Rol, DosFactor, Telefono) VALUES
    (N'Vendedor Demo', N'Vendedor', N'Demo', N'VEN-0001', N'vendedor@pedidos.local',
     N'$2a$11$oFp4Su1EGJ.wZ2.Kt13t..t1cMYLEPasMvtAK/XKWj28ldCnZYb0q', N'VENDEDOR', N'NINGUNO', N'+50255550102'),
    (N'Administrador General', N'Administrador', N'General', N'ADM-0001', N'admin@pedidos.local',
     N'$2a$11$E6LutlNGkp4N/dpe38.jW.ZfVU6YeW/D4mgxag/fpqIMZWisZA4FW', N'ADMIN', N'NINGUNO', N'+50255550101');
GO

-- Usuarios de demostración de los roles del ERP (se agregan también a una BD existente).
INSERT INTO dbo.Usuarios (Username, Nombre, Apellido, CodigoCorporativo, Email, PasswordHash, Rol, DosFactor, Telefono)
SELECT u.Username, u.Nombre, u.Apellido, u.Codigo, u.Email, u.Hash, u.Rol, N'NINGUNO', u.Telefono
  FROM (VALUES
    (N'Bodega Demo', N'Bodega', N'Demo', N'BOD-0001', N'bodega@pedidos.local',
     N'$2a$11$DcvNL1n5aOQr31oWKErOEeN6StaBnirH/H4LSNzXxRJqQkZ0ZB6FO', N'BODEGA', N'+50255550103'),
    (N'Compras Demo', N'Compras', N'Demo', N'COM-0001', N'compras@pedidos.local',
     N'$2a$11$lk46wuJUh20Uid6ZZerOd.ZX0UOROh8allG0Tp5QVxTGpWcOEkI1W', N'COMPRAS', N'+50255550104'),
    (N'Contador Demo', N'Contador', N'Demo', N'CON-0001', N'contador@pedidos.local',
     N'$2a$11$N5znA8RpJJQ0kxoIaf3SrezhLdUAdcpjscJd1oyLZYRaD.QCtKAbS', N'CONTADOR', N'+50255550105')
  ) AS u (Username, Nombre, Apellido, Codigo, Email, Hash, Rol, Telefono)
 WHERE NOT EXISTS (SELECT 1 FROM dbo.Usuarios x WHERE x.Email = u.Email OR x.CodigoCorporativo = u.Codigo);
GO

-- Precios con IVA; costos promedio sin IVA.
IF NOT EXISTS (SELECT 1 FROM dbo.Productos)
INSERT INTO dbo.Productos (Codigo, Nombre, Precio, Stock, CostoPromedio, StockMinimo) VALUES
    (N'P-001', N'Teclado mecánico',    450.00, 25,  260.00,  5),
    (N'P-002', N'Mouse inalámbrico',   125.50, 40,   70.00, 10),
    (N'P-003', N'Monitor 27"',        2350.00,  1, 1450.00,  2),  -- stock 1: para probar la regla de concurrencia
    (N'P-004', N'Audífonos USB',       199.99, 12,  110.00,  5),
    (N'P-005', N'Webcam HD',           310.00,  0,  180.00,  3);  -- sin stock: se muestra deshabilitado en el catálogo
GO

-- Fichas de los productos semilla (solo si aún no tienen descripción; no pisa lo que se edite en la app).
UPDATE p SET Marca = f.Marca, Categoria = f.Categoria, Descripcion = f.Descripcion, GarantiaMeses = f.Garantia,
             Especificaciones = f.Especificaciones
  FROM dbo.Productos p
  JOIN (VALUES
    (N'P-001', N'KeyForge', N'Periféricos', 12,
     N'Teclado mecánico de tamaño completo pensado para jornadas largas de digitación y para gaming. Sus interruptores lineales rojos tienen un recorrido suave y silencioso, con una fuerza de activación de 45 g que reduce la fatiga de los dedos.' + NCHAR(10) + NCHAR(10) +
     N'La estructura de aluminio le da firmeza y evita que se deslice en el escritorio. Las teclas de doble inyección no se borran con el uso, y la retroiluminación blanca tiene 5 niveles de brillo para trabajar de noche.' + NCHAR(10) + NCHAR(10) +
     N'Incluye reposamuñecas desmontable, cable USB-C trenzado de 1.8 m y extractor de teclas. Distribución en español latinoamericano (con Ñ).',
     N'[{"Nombre":"Interruptores","Valor":"Mecánicos lineales rojos, 45 g, 50 millones de pulsaciones"},{"Nombre":"Distribución","Valor":"Español latinoamericano, 105 teclas"},{"Nombre":"Conexión","Valor":"USB-C desmontable (cable trenzado de 1.8 m)"},{"Nombre":"Iluminación","Valor":"LED blanca, 5 niveles"},{"Nombre":"Anti-ghosting","Valor":"N-key rollover completo"},{"Nombre":"Material","Valor":"Placa de aluminio, teclas PBT de doble inyección"},{"Nombre":"Dimensiones","Valor":"44 x 13.5 x 3.8 cm"},{"Nombre":"Peso","Valor":"1.05 kg"},{"Nombre":"Compatibilidad","Valor":"Windows, macOS y Linux"}]'),
    (N'P-002', N'Orion', N'Periféricos', 12,
     N'Mouse inalámbrico ergonómico con doble conexión: receptor USB de 2.4 GHz para una respuesta sin retraso y Bluetooth para usarlo con laptop, tablet o teléfono. Cambia entre dispositivos con un botón.' + NCHAR(10) + NCHAR(10) +
     N'Su sensor óptico de 4,000 DPI funciona sobre casi cualquier superficie, y los clics silenciosos lo hacen ideal para oficinas compartidas. La batería recargable dura hasta 70 días con una carga completa por USB-C.',
     N'[{"Nombre":"Sensor","Valor":"Óptico, 800 a 4,000 DPI (4 niveles)"},{"Nombre":"Conexión","Valor":"Receptor USB 2.4 GHz y Bluetooth 5.1"},{"Nombre":"Botones","Valor":"6 (clic silencioso, rueda y 2 laterales)"},{"Nombre":"Batería","Valor":"Recargable 500 mAh, hasta 70 días"},{"Nombre":"Carga","Valor":"USB-C (cable incluido)"},{"Nombre":"Alcance","Valor":"Hasta 10 m"},{"Nombre":"Peso","Valor":"92 g"}]'),
    (N'P-003', N'Vista', N'Monitores', 36,
     N'Monitor de 27 pulgadas con panel IPS y resolución QHD (2560 x 1440): colores fieles desde cualquier ángulo y 77 % más espacio de trabajo que un monitor Full HD. Ideal para diseño, hojas de cálculo y trabajo con varias ventanas.' + NCHAR(10) + NCHAR(10) +
     N'La tasa de refresco de 75 Hz y la tecnología FreeSync dan una imagen fluida, y el modo de luz azul reducida con pantalla sin parpadeo cuida la vista. La base ajusta altura, inclinación y giro, y es compatible con soportes VESA.',
     N'[{"Nombre":"Tamaño","Valor":"27 pulgadas"},{"Nombre":"Panel","Valor":"IPS, antirreflejo"},{"Nombre":"Resolución","Valor":"2560 x 1440 (QHD)"},{"Nombre":"Frecuencia","Valor":"75 Hz con FreeSync"},{"Nombre":"Tiempo de respuesta","Valor":"5 ms"},{"Nombre":"Color","Valor":"99 % sRGB, 1,000:1"},{"Nombre":"Entradas","Valor":"2 HDMI 2.0, 1 DisplayPort 1.4, salida de audio"},{"Nombre":"Ergonomía","Valor":"Altura, inclinación, giro y pivote; VESA 100 x 100"},{"Nombre":"Consumo","Valor":"28 W típico"}]'),
    (N'P-004', N'SonicWave', N'Audio', 6,
     N'Audífonos USB con micrófono con cancelación de ruido, diseñados para videollamadas, clases en línea y centros de atención. Se conectan y funcionan al instante, sin instalar controladores.' + NCHAR(10) + NCHAR(10) +
     N'Las almohadillas de espuma viscoelástica y la diadema acolchada permiten usarlos todo el día. El control en el cable sube o baja el volumen y silencia el micrófono, y el micrófono se retrae dentro de la diadema cuando no se usa.',
     N'[{"Nombre":"Tipo","Valor":"Diadema, sobre la oreja, estéreo"},{"Nombre":"Conexión","Valor":"USB-A, cable de 2 m"},{"Nombre":"Micrófono","Valor":"Omnidireccional con cancelación de ruido, retráctil"},{"Nombre":"Respuesta","Valor":"20 Hz a 20 kHz"},{"Nombre":"Controles","Valor":"Volumen y silencio en el cable"},{"Nombre":"Peso","Valor":"180 g"},{"Nombre":"Certificación","Valor":"Compatible con Teams, Zoom y Meet"}]'),
    (N'P-005', N'ClearCam', N'Video', 12,
     N'Cámara web Full HD 1080p a 30 cuadros por segundo con enfoque automático y corrección de luz: se ve con nitidez incluso en oficinas con poca iluminación.' + NCHAR(10) + NCHAR(10) +
     N'Trae dos micrófonos estéreo con reducción de ruido y una tapa de privacidad deslizable. El clip universal se ajusta a monitores y laptops, o se atornilla a un trípode.',
     N'[{"Nombre":"Resolución","Valor":"1920 x 1080 a 30 fps"},{"Nombre":"Enfoque","Valor":"Automático"},{"Nombre":"Campo de visión","Valor":"78 grados"},{"Nombre":"Micrófono","Valor":"Doble, estéreo, con reducción de ruido"},{"Nombre":"Conexión","Valor":"USB-A, cable de 1.5 m"},{"Nombre":"Privacidad","Valor":"Tapa deslizable"},{"Nombre":"Montaje","Valor":"Clip universal y rosca para trípode"}]')
  ) AS f (Codigo, Marca, Categoria, Garantia, Descripcion, Especificaciones)
    ON f.Codigo = p.Codigo
 WHERE p.Descripcion IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Proveedores)
INSERT INTO dbo.Proveedores (Nit, Nombre, Contacto, Telefono, Email, Direccion) VALUES
    (N'33445567', N'Distribuidora Tecnológica, S.A.', N'Ana Pérez', N'+50222220101', N'ventas@distritec.example', N'Zona 4, Ciudad de Guatemala'),
    (N'66778891', N'Importadora del Pacífico, S.A.', N'Luis Gómez', N'+50277770202', N'pedidos@impacifico.example', N'Escuintla');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Clientes WHERE Nit <> N'CF')
INSERT INTO dbo.Clientes (Nit, Nombre, Direccion, Telefono) VALUES
    (N'12345679', N'Comercial La Esquina', N'6a. avenida 10-20, zona 1', N'+50222330101'),
    (N'8899001K', N'Ferretería El Martillo', N'Mixco', NULL);
GO

-- ---------- Apertura del ERP (una sola vez) ----------
-- Da costo a los productos que no lo tienen, registra la existencia inicial en el kardex y la partida de
-- apertura (bancos e inventario contra capital), para que inventario y contabilidad arranquen cuadrados.
IF NOT EXISTS (SELECT 1 FROM dbo.Partidas WHERE Origen = N'APERTURA')
BEGIN
    BEGIN TRANSACTION;

    UPDATE dbo.Productos SET CostoPromedio = ROUND(Precio / 1.12 * 0.60, 2) WHERE CostoPromedio = 0;
    UPDATE dbo.Productos SET StockMinimo = 5 WHERE StockMinimo = 0;

    -- Ventas anteriores al ERP: costo aproximado al costo inicial (no tienen partida: son previas a la apertura).
    UPDATE d SET CostoUnitario = p.CostoPromedio
      FROM dbo.PedidoDetalle d JOIN dbo.Productos p ON p.Id = d.ProductoId
     WHERE d.CostoUnitario = 0;
    UPDATE pe SET Costo = x.Costo
      FROM dbo.Pedidos pe
      JOIN (SELECT PedidoId, SUM(ROUND(Cantidad * CostoUnitario, 2)) AS Costo FROM dbo.PedidoDetalle GROUP BY PedidoId) x
        ON x.PedidoId = pe.Id
     WHERE pe.Costo = 0;

    INSERT INTO dbo.MovimientosInventario (ProductoId, Fecha, Tipo, Cantidad, CostoUnitario, Saldo, CostoPromedio, Referencia, UsuarioId)
    SELECT Id, SYSUTCDATETIME(), N'INICIAL', Stock, CostoPromedio, Stock, CostoPromedio, N'Inventario inicial', NULL
      FROM dbo.Productos
     WHERE Stock > 0;

    DECLARE @inventario DECIMAL(18,2) = (SELECT COALESCE(SUM(ROUND(Stock * CostoPromedio, 2)), 0) FROM dbo.Productos);
    DECLARE @bancos DECIMAL(18,2) = 100000.00;
    DECLARE @hoy DATE = CAST(DATEADD(HOUR, -6, SYSUTCDATETIME()) AS DATE);

    INSERT INTO dbo.Partidas (Fecha, Concepto, Origen, ReferenciaId, UsuarioId, CreadoEn, Total)
    VALUES (@hoy, N'Partida de apertura: saldo inicial en bancos e inventario', N'APERTURA', NULL, NULL, SYSUTCDATETIME(),
            @bancos + @inventario);
    DECLARE @partida INT = SCOPE_IDENTITY();

    INSERT INTO dbo.PartidaDetalle (PartidaId, CuentaId, Debe, Haber)
    SELECT @partida, Id, @bancos, 0 FROM dbo.CuentasContables WHERE Codigo = N'1102'
    UNION ALL
    SELECT @partida, Id, @inventario, 0 FROM dbo.CuentasContables WHERE Codigo = N'1103' AND @inventario > 0
    UNION ALL
    SELECT @partida, Id, 0, @bancos + @inventario FROM dbo.CuentasContables WHERE Codigo = N'3101';

    COMMIT TRANSACTION;
END
GO

-- ---------- Login de la aplicación con permisos mínimos ----------
-- La API no usa "sa": solo puede leer y escribir datos, no alterar el esquema.
USE [master];
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$(APP_DB_USER)')
    CREATE LOGIN [$(APP_DB_USER)] WITH PASSWORD = N'$(APP_DB_PASSWORD)', CHECK_POLICY = ON;
GO
USE [$(DB_NAME)];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(APP_DB_USER)')
BEGIN
    CREATE USER [$(APP_DB_USER)] FOR LOGIN [$(APP_DB_USER)];
    ALTER ROLE db_datareader ADD MEMBER [$(APP_DB_USER)];
    ALTER ROLE db_datawriter ADD MEMBER [$(APP_DB_USER)];
END
GO

PRINT N'Base de datos $(DB_NAME) inicializada.';
GO
