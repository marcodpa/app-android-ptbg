-- ============================================================================
--  STER · Rol de administrador y bitácora de eventos
--  Planta Termoeléctrica Bajo Grande · MariaDB
--
--  Qué hace este script:
--    PASO 1  Revisa (solo lee) cómo está hecha MDB_USERS.
--    PASO 2  Crea MOT_LOG_ADM, la bitácora de lo que hace el administrador.
--    PASO 3  Da de alta a DANIEL BERRUETA como administrador.
--    PASO 4  Verifica que todo quedó bien.
--
--  Ejecutar los pasos EN ORDEN, uno por uno, leyendo el resultado de cada
--  uno antes de seguir. El PASO 1 no modifica nada.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- PASO 1 · Reconocimiento (no modifica nada)
-- ----------------------------------------------------------------------------
-- 1.a) Cómo está definida la tabla de usuarios. Mirar dos cosas:
--        · si ID es AUTO_INCREMENT  -> usar el INSERT 3.a
--        · si ID NO es AUTO_INCREMENT -> usar el INSERT 3.b
--      y de paso el ENGINE y el CHARSET, para que la tabla nueva quede igual.
SHOW CREATE TABLE MDB_USERS;

-- 1.b) Quién existe hoy y con qué cargo.
SELECT ID, USUARIO, CARGO
FROM MDB_USERS
ORDER BY USUARIO;

-- 1.c) Comprobar que Daniel todavía no está (debe devolver 0 filas).
SELECT ID, USUARIO, CARGO
FROM MDB_USERS
WHERE UPPER(TRIM(USUARIO)) LIKE '%BERRUETA%';


-- ----------------------------------------------------------------------------
-- PASO 2 · La tabla nueva: MOT_LOG_ADM
-- ----------------------------------------------------------------------------
-- Bitácora de lo que SOLO puede hacer el administrador: corregir una medición
-- ya capturada y retro-fechar una medición hecha sin la tablet a mano.
--
-- Reglas de lectura de esta tabla:
--   · FECHA/HORA son las del RELOJ REAL de la tablet, el momento en que el
--     administrador hizo el cambio. NUNCA la fecha que él eligió. Si retro-
--     fechó una medición al día anterior, eso aparece en DETALLE, no aquí.
--   · UUID identifica el evento y es único: si una subida se corta y se
--     reintenta, el evento no se duplica.
--   · UUID_MEDICION apunta al UUID de la medición tocada, así se puede cruzar
--     con MOT_VIBR_MUES, MOT_TEMP_MUES, MOT_LUB_REG o MOT_ALN_REG.
--   · Nadie edita ni borra esta tabla desde la aplicación: solo se inserta.
--
-- Si el PASO 1.a mostró otro ENGINE o CHARSET en MDB_USERS, ajustar las dos
-- últimas líneas para que coincidan con el resto de la base.

CREATE TABLE IF NOT EXISTS MOT_LOG_ADM (
  ID             INT           NOT NULL AUTO_INCREMENT,
  UUID           CHAR(36)      NOT NULL COMMENT 'Identificador del evento; único',
  FECHA          DATE          NOT NULL COMMENT 'Fecha REAL en que el admin hizo el cambio',
  HORA           TIME          NOT NULL COMMENT 'Hora REAL en que el admin hizo el cambio',
  USUARIO        VARCHAR(80)   NOT NULL COMMENT 'Quién lo hizo',
  CARGO          VARCHAR(60)       NULL,
  ACCION         VARCHAR(30)   NOT NULL COMMENT 'EDICION | FECHA MANUAL',
  SERVICIO       VARCHAR(30)       NULL COMMENT 'vibracion, temperatura, lubricacion, alineacion, reemplazo',
  LOCALIZACION   INT               NULL COMMENT 'Equipo afectado (MOT_EQUIPO.LOCALIZACION)',
  UUID_MEDICION  VARCHAR(60)       NULL COMMENT 'UUID de la medición corregida',
  DETALLE        TEXT              NULL COMMENT 'Qué cambió: "T2: 88.0 -> 90.5 · obs: RUIDO -> SIN NOVEDAD"',
  TABLET         VARCHAR(40)       NULL COMMENT 'Serial de la tablet de origen',
  CREATED_AT     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Cuándo llegó a la planta',
  PRIMARY KEY (ID),
  UNIQUE KEY UX_MOT_LOG_ADM_UUID (UUID),
  KEY IX_MOT_LOG_ADM_FECHA (FECHA, HORA),
  KEY IX_MOT_LOG_ADM_USUARIO (USUARIO),
  KEY IX_MOT_LOG_ADM_LOC (LOCALIZACION),
  KEY IX_MOT_LOG_ADM_MEDICION (UUID_MEDICION)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_general_ci
  COMMENT='STER: bitacora de correcciones y retro-fechados del administrador';


-- ----------------------------------------------------------------------------
-- PASO 3 · Dar de alta a DANIEL BERRUETA
-- ----------------------------------------------------------------------------
-- La aplicación lo reconoce como administrador de dos maneras, con que se
-- cumpla una basta:
--     a) el nombre es DANIEL BERRUETA (va fijo en la app), o
--     b) su CARGO contiene la palabra ADMIN.
-- Por eso se le pone cargo 'ADMIN': así queda explícito en la base y, si
-- mañana nombran a otro administrador, basta con darle ese mismo cargo aquí
-- —sin tocar la aplicación ni instalar un APK nuevo.
--
-- El nombre va EN MAYÚSCULAS y sin acentos, como el resto de los usuarios.

-- 3.a) SI ID ES AUTO_INCREMENT (lo normal):
INSERT INTO MDB_USERS (USUARIO, CARGO)
SELECT 'DANIEL BERRUETA', 'ADMIN'
WHERE NOT EXISTS (
  SELECT 1 FROM MDB_USERS WHERE UPPER(TRIM(USUARIO)) = 'DANIEL BERRUETA'
);

-- 3.b) SI ID **NO** ES AUTO_INCREMENT, usar este en lugar del anterior:
-- INSERT INTO MDB_USERS (ID, USUARIO, CARGO)
-- SELECT COALESCE(MAX(ID), 0) + 1, 'DANIEL BERRUETA', 'ADMIN'
-- FROM MDB_USERS
-- WHERE NOT EXISTS (
--   SELECT 1 FROM MDB_USERS WHERE UPPER(TRIM(USUARIO)) = 'DANIEL BERRUETA'
-- );

-- 3.c) Si Daniel YA existía como mecánico y solo hay que ascenderlo:
-- UPDATE MDB_USERS
-- SET CARGO = 'ADMIN'
-- WHERE UPPER(TRIM(USUARIO)) = 'DANIEL BERRUETA';


-- ----------------------------------------------------------------------------
-- PASO 4 · Verificación
-- ----------------------------------------------------------------------------
-- 4.a) La tabla nueva existe y está vacía (0 filas es lo correcto hoy).
SELECT COUNT(*) AS eventos_registrados FROM MOT_LOG_ADM;

-- 4.b) Daniel quedó como administrador (debe devolver exactamente 1 fila).
SELECT ID, USUARIO, CARGO
FROM MDB_USERS
WHERE UPPER(TRIM(USUARIO)) = 'DANIEL BERRUETA';

-- 4.c) Quiénes son administradores hoy.
SELECT ID, USUARIO, CARGO
FROM MDB_USERS
WHERE UPPER(CARGO) LIKE '%ADMIN%'
   OR UPPER(TRIM(USUARIO)) = 'DANIEL BERRUETA'
ORDER BY USUARIO;


-- ============================================================================
--  CONSULTAS DE AUDITORÍA (para el día a día, no hace falta correrlas ahora)
-- ============================================================================

-- Todo lo que hizo el administrador, lo más reciente primero.
-- SELECT FECHA, HORA, USUARIO, ACCION, SERVICIO, LOCALIZACION, DETALLE
-- FROM MOT_LOG_ADM
-- ORDER BY FECHA DESC, HORA DESC;

-- Solo las mediciones que se guardaron con fecha distinta a la del día.
-- SELECT FECHA AS registrado_el, HORA AS registrado_a_las,
--        USUARIO, SERVICIO, LOCALIZACION, DETALLE
-- FROM MOT_LOG_ADM
-- WHERE ACCION = 'FECHA MANUAL'
-- ORDER BY FECHA DESC, HORA DESC;

-- Cuánto tocó cada administrador en el último mes.
-- SELECT USUARIO, ACCION, COUNT(*) AS veces
-- FROM MOT_LOG_ADM
-- WHERE FECHA >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
-- GROUP BY USUARIO, ACCION
-- ORDER BY veces DESC;

-- Historial de un equipo: qué le corrigieron y cuándo.
-- SELECT FECHA, HORA, USUARIO, ACCION, SERVICIO, DETALLE
-- FROM MOT_LOG_ADM
-- WHERE LOCALIZACION = 48        -- <- cambiar por la localización que interese
-- ORDER BY FECHA DESC, HORA DESC;

-- Temperaturas que fueron corregidas después de subir, cruzando por UUID.
-- SELECT m.LOCALIZACION, m.FECHA AS fecha_medicion, m.HORA AS hora_medicion,
--        a.USUARIO AS corregida_por, a.FECHA AS fecha_correccion, a.DETALLE
-- FROM MOT_LOG_ADM a
-- JOIN MOT_TEMP_MUES m ON m.UUID = a.UUID_MEDICION
-- WHERE a.SERVICIO = 'temperatura'
-- ORDER BY a.FECHA DESC, a.HORA DESC;


-- ============================================================================
--  MARCHA ATRÁS (solo si hiciera falta deshacer)
-- ============================================================================
-- OJO: al borrar la tabla se pierde la bitácora. Exportarla antes.
-- DROP TABLE IF EXISTS MOT_LOG_ADM;
-- DELETE FROM MDB_USERS WHERE UPPER(TRIM(USUARIO)) = 'DANIEL BERRUETA';
