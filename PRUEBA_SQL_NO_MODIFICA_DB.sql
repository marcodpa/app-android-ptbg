-- Prueba de lectura. No modifica la base de datos.
SELECT
    e.ID_EQ,
    e.EQUIPO,
    e.LC_EQ,
    e.PT_EQ,
    e.TG_EQ,
    i.MARCA_INFO,
    i.SERIAL_INFO,
    i.MODEL_INFO,
    i.HP_INFO,
    i.VOLTS_INFO,
    i.RPM_INFO
FROM MOT_EQUIPO e
LEFT JOIN MOT_INFO i ON i.LC_EQ = e.LC_EQ
ORDER BY e.ID_EQ;
