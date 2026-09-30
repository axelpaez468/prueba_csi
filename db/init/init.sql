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
-- Login de ERP: correo, 2FA (app autenticadora / SMS), recuperación de contraseña y bitácora.
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
        CONSTRAINT CK_Usuarios_DosFactor CHECK (DosFactor IN (N'NINGUNO', N'TOTP', N'SMS'));
IF COL_LENGTH(N'dbo.Usuarios', N'TotpSecretoCifrado') IS NULL
    ALTER TABLE dbo.Usuarios ADD TotpSecretoCifrado NVARCHAR(200) NULL;   -- AES-GCM, nunca en claro
IF COL_LENGTH(N'dbo.Usuarios', N'TotpUltimoPaso') IS NULL
    ALTER TABLE dbo.Usuarios ADD TotpUltimoPaso BIGINT NULL;              -- anti-reutilización de códigos
IF COL_LENGTH(N'dbo.Usuarios', N'TotpPendienteCifrado') IS NULL
    ALTER TABLE dbo.Usuarios ADD TotpPendienteCifrado NVARCHAR(200) NULL;
IF COL_LENGTH(N'dbo.Usuarios', N'TelefonoPendiente') IS NULL
    ALTER TABLE dbo.Usuarios ADD TelefonoPendiente NVARCHAR(20) NULL;
IF COL_LENGTH(N'dbo.Usuarios', N'VersionSesion') IS NULL
    ALTER TABLE dbo.Usuarios ADD VersionSesion INT NOT NULL CONSTRAINT DF_Usuarios_VersionSesion DEFAULT (0);
GO

-- BD existente con los usuarios originales: se les asigna correo, y el admin pasa a tener 2FA por SMS.
UPDATE dbo.Usuarios SET Email = LOWER(Username) + N'@pedidos.local' WHERE Email IS NULL;
UPDATE dbo.Usuarios
   SET PasswordHash = N'$2a$11$E6LutlNGkp4N/dpe38.jW.ZfVU6YeW/D4mgxag/fpqIMZWisZA4FW',
       DosFactor = N'SMS', Telefono = N'+50255550101', VersionSesion = VersionSesion + 1
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

IF OBJECT_ID(N'dbo.CodigosVerificacion', N'U') IS NULL
CREATE TABLE dbo.CodigosVerificacion (
    Id         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CodigosVerificacion PRIMARY KEY,
    UsuarioId  INT          NOT NULL CONSTRAINT FK_CodigosVerificacion_Usuarios REFERENCES dbo.Usuarios(Id) ON DELETE CASCADE,
    Proposito  NVARCHAR(20) NOT NULL,
    CodigoHash CHAR(64)     NOT NULL,
    ExpiraEn   DATETIME2    NOT NULL,
    Intentos   INT          NOT NULL CONSTRAINT DF_CodigosVerificacion_Intentos DEFAULT (0),
    UsadoEn    DATETIME2    NULL,
    CreadoEn   DATETIME2    NOT NULL,
    INDEX IX_CodigosVerificacion_Usuario (UsuarioId, Proposito)
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

-- ---------- Datos semilla ----------
-- Hashes BCrypt (work factor 11). Contraseñas de prueba documentadas en el README.
-- El admin tiene 2FA por SMS (obligatorio para su rol); los SMS se ven en la bandeja de Mailpit.
IF NOT EXISTS (SELECT 1 FROM dbo.Usuarios)
INSERT INTO dbo.Usuarios (Username, Email, PasswordHash, Rol, DosFactor, Telefono) VALUES
    (N'vendedor', N'vendedor@pedidos.local', N'$2a$11$oFp4Su1EGJ.wZ2.Kt13t..t1cMYLEPasMvtAK/XKWj28ldCnZYb0q', N'VENDEDOR', N'NINGUNO', NULL),
    (N'admin',    N'admin@pedidos.local',    N'$2a$11$E6LutlNGkp4N/dpe38.jW.ZfVU6YeW/D4mgxag/fpqIMZWisZA4FW', N'ADMIN',    N'SMS',     N'+50255550101');
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
