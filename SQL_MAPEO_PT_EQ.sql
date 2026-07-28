-- =============================================================
-- MAPEO VISUAL OFICIAL POR BASE DE DATOS
-- Tabla: MOT_EQUIPO
-- Columna: PT_EQ
--
-- La app V13 NO decide la imagen por nombre ni por LC_EQ.
-- La app usa SOLO el valor de MOT_EQUIPO.PT_EQ.
-- =============================================================

-- Ejecutar una sola vez si la columna no existe:
ALTER TABLE MOT_EQUIPO ADD COLUMN IF NOT EXISTS PT_EQ INT DEFAULT 1;

-- Mapeo definido por Juan según el PDF:
-- PT_EQ = 1 -> PDF página 1
-- PT_EQ = 2 -> PDF página 5
-- PT_EQ = 3 -> PDF página 9
-- PT_EQ = 4 -> PDF página 13
-- PT_EQ = 5 -> PDF página 16
-- PT_EQ = 6 -> PDF página 20
-- PT_EQ = 7 -> PDF página 26
-- PT_EQ = 8 -> PDF página 28
-- PT_EQ = 9 -> PDF página 30

-- Ejemplos según la tabla mostrada:
-- OJO: ajusta aquí cada LC_EQ según lo que tú decidas en la base de datos.

-- PT_EQ 4: Ventiladores de turbina. También FIN FAN A/B de BG2 si quieres que usen esa misma foto.
UPDATE MOT_EQUIPO SET PT_EQ = 4 WHERE LC_EQ IN (4,5,11,12,16,18,47);

-- PT_EQ 5: Fin fan / ventilador generador restantes.
UPDATE MOT_EQUIPO SET PT_EQ = 5 WHERE LC_EQ IN (6,7,13,14,15,17);

-- Otros ejemplos de referencia:
UPDATE MOT_EQUIPO SET PT_EQ = 6 WHERE LC_EQ IN (2,3,9,10,46); -- NOX
UPDATE MOT_EQUIPO SET PT_EQ = 9 WHERE LC_EQ IN (19,21);      -- HYD STARTER
UPDATE MOT_EQUIPO SET PT_EQ = 8 WHERE LC_EQ IN (20,22);      -- SPRINT
UPDATE MOT_EQUIPO SET PT_EQ = 2 WHERE LC_EQ = 31;            -- SCI ELECTRIC MOTOR
UPDATE MOT_EQUIPO SET PT_EQ = 7 WHERE LC_EQ = 32;            -- JOCKEY MOTOR
UPDATE MOT_EQUIPO SET PT_EQ = 3 WHERE LC_EQ = 33;            -- DIESEL MOTOR

-- Verificación obligatoria:
SELECT ID_EQ, EQUIPO, LC_EQ, PT_EQ, TG_EQ
FROM MOT_EQUIPO
ORDER BY LC_EQ;
