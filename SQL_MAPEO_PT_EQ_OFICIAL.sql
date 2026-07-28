-- =============================================================
-- SCV-PTBG: MAPEO OFICIAL DE IMAGENES POR BASE DE DATOS
-- Tabla: MOT_EQUIPO
-- Columna: PT_EQ
-- =============================================================

-- 1) Crear columna si no existe.
-- Si tu MariaDB no acepta IF NOT EXISTS, ejecuta solo:
-- ALTER TABLE MOT_EQUIPO ADD COLUMN PT_EQ INT DEFAULT 1;
ALTER TABLE MOT_EQUIPO ADD COLUMN IF NOT EXISTS PT_EQ INT DEFAULT 1;

-- 2) Valor por defecto: si no se configura, usa tipo 1.
UPDATE MOT_EQUIPO SET PT_EQ = 1 WHERE PT_EQ IS NULL OR PT_EQ = 0;

-- =============================================================
-- MAPEO DEFINIDO POR JUAN SEGUN PDF
-- PT_EQ = 1 -> PDF pagina 1
-- PT_EQ = 2 -> PDF pagina 5
-- PT_EQ = 3 -> PDF pagina 9
-- PT_EQ = 4 -> PDF pagina 13
-- PT_EQ = 5 -> PDF pagina 16
-- PT_EQ = 6 -> PDF pagina 20
-- PT_EQ = 7 -> PDF pagina 26
-- PT_EQ = 8 -> PDF pagina 28
-- PT_EQ = 9 -> PDF pagina 30
-- =============================================================

-- Estos UPDATE son sugeridos segun lo que se ve en tu tabla.
-- Puedes modificarlos si decides otro PT_EQ para algun LC_EQ.

-- NOX / bomba-reductor: pagina 20
UPDATE MOT_EQUIPO SET PT_EQ = 6 WHERE LC_EQ IN (2,3,9,10,46);

-- Ventiladores turbina / ven turb A-B: pagina 13
-- Juan: FIN FAN A y FIN FAN B de BG2 deben usar la misma foto de VEN TURB A/B.
-- En la tabla mostrada son LC_EQ 16 y 18.
UPDATE MOT_EQUIPO SET PT_EQ = 4 WHERE LC_EQ IN (4,5,11,12,16,18,47);

-- Fin fan restantes: pagina 16
UPDATE MOT_EQUIPO SET PT_EQ = 5 WHERE LC_EQ IN (6,7,13,14,15,17);

-- Starter hidraulico: pagina 30
UPDATE MOT_EQUIPO SET PT_EQ = 9 WHERE LC_EQ IN (19,21);

-- Sprint: pagina 28
UPDATE MOT_EQUIPO SET PT_EQ = 8 WHERE LC_EQ IN (20,22);

-- SCI electric motor: pagina 5
UPDATE MOT_EQUIPO SET PT_EQ = 2 WHERE LC_EQ = 31;

-- Jockey: pagina 26
UPDATE MOT_EQUIPO SET PT_EQ = 7 WHERE LC_EQ = 32;

-- Diesel motor: pagina 9
UPDATE MOT_EQUIPO SET PT_EQ = 3 WHERE LC_EQ = 33;

-- Bomba general / motor bomba horizontal: pagina 1
-- Ajusta aqui los LC_EQ que correspondan a este tipo.
UPDATE MOT_EQUIPO SET PT_EQ = 1 WHERE LC_EQ IN (23,24,25,26,27,28,29,30,34,35,36,37,38,39,40,41,42,43,44,45);

-- 3) Verificacion obligatoria.
SELECT ID_EQ, EQUIPO, LC_EQ, PT_EQ, TG_EQ
FROM MOT_EQUIPO
ORDER BY LC_EQ;
