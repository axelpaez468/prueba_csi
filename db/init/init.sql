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

-- ---------- Datos semilla ----------
-- Hashes BCrypt (work factor 11). Contraseñas de prueba documentadas en el README.
IF NOT EXISTS (SELECT 1 FROM dbo.Usuarios)
INSERT INTO dbo.Usuarios (Username, PasswordHash, Rol) VALUES
    (N'vendedor', N'$2a$11$oFp4Su1EGJ.wZ2.Kt13t..t1cMYLEPasMvtAK/XKWj28ldCnZYb0q', N'VENDEDOR'),
    (N'admin',    N'$2a$11$3Rr3e98FiYcYHxN0LxYRQ.KwgRgK3LxXkO0orwnBuY9sH4yUIlP8O', N'ADMIN');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Productos)
INSERT INTO dbo.Productos (Codigo, Nombre, Precio, Stock) VALUES
    (N'P-001', N'Teclado mecánico',    450.00, 25),
    (N'P-002', N'Mouse inalámbrico',   125.50, 40),
    (N'P-003', N'Monitor 27"',        2350.00,  1),  -- stock 1: para probar la regla de concurrencia
    (N'P-004', N'Audífonos USB',       199.99, 12),
    (N'P-005', N'Webcam HD',           310.00,  0);  -- sin stock: se muestra deshabilitado en el catálogo
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
