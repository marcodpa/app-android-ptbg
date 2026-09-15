import sqlite3
import subprocess
import sys
from pathlib import Path


def main(path: str) -> None:
    connection = sqlite3.connect(path)
    try:
        for name, sql in connection.execute(
            "SELECT name, sql FROM sqlite_master "
            "WHERE type = 'table' ORDER BY name"
        ):
            print(f"{name}: {sql}")
    finally:
        connection.close()


def pull_database(adb: str, destination: str) -> None:
    result = subprocess.run(
        [
            adb,
            "exec-out",
            "run-as",
            "com.example.scv_ptbg",
            "cat",
            "databases/scv_ptbg.db",
        ],
        check=True,
        stdout=subprocess.PIPE,
    )
    Path(destination).write_bytes(result.stdout)


def seed_database(path: str) -> None:
    connection = sqlite3.connect(path)
    try:
        connection.execute("DELETE FROM EQUIPOS")
        connection.execute("DELETE FROM EQUIPO_INFO")
        connection.execute(
            """
            INSERT INTO EQUIPOS
              (ID, CODE_SYS, EQUIPO, LOCALIZACION, QR_CODE, PUNTOS, PT_EQ,
               SISTEMA, SUBSISTEMA, SCADA)
            VALUES
              (9001, 501, 'BOMBA DE AGUA INDUSTRIAL', 9901, 'STER-DEMO-9901',
               6, 6, 'SERVICIOS AUXILIARES', 'SISTEMA DE AGUA', 'DEMO-9901'),
              (9002, 502, 'VENTILADOR FIN-FAN', 9902, 'STER-DEMO-9902',
               4, 4, 'ENFRIAMIENTO', 'FIN-FAN PRINCIPAL', 'DEMO-9902'),
              (9003, 503, 'VENTILADOR TORRE', 9903, 'STER-DEMO-9903',
               5, 5, 'TORRE DE ENFRIAMIENTO', 'CELDA A', 'DEMO-9903')
            """
        )
        connection.executemany(
            """
            INSERT INTO EQUIPO_INFO
              (localizacion, marca, serial, modelo, hp, start, volts, fla, sf,
               hz, ph, rpm, brgs_drive, brgs_opp, lubricacion, motores_lub,
               cant_mot_lub, elec_mot_lub, man_mot_lub, elemento_lub,
               cant_elem_lub, elec_elem_lub, man_elem_lub)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (9901, 'WEG', 'MTR-DEMO-001', 'W22 IE3', '75', 'ESTRELLA-TRIANGULO',
                 '460', '92', '1.15', '60', '3', '1780', '6312-C3', '6312-C3',
                 'GRASA EP2', 'MOTOR PRINCIPAL', 55, 28, 23,
                 'ACOPLAMIENTO', 110, 55, 46),
                (9902, 'SIEMENS', 'FIN-DEMO-002', '1LE1', '30', 'DIRECTO',
                 '460', '38', '1.15', '60', '3', '1775', '6309-C3', '6309-C3',
                 'GRASA EP2', 'MOTOR FIN-FAN', 22, 11, 9,
                 'RODAMIENTO FIN-FAN', None, None, None),
                (9903, 'ABB', 'VENT-DEMO-003', 'M3BP', '40', 'DIRECTO',
                 '460', '48', '1.15', '60', '3', '1785', '6310-C3', '6310-C3',
                 'GRASA EP2', 'MOTOR VENTILADOR', 35, 18, 15,
                 'VENTILADORES', None, 4, 3),
            ],
        )
        connection.execute("DELETE FROM ORDENES_TRABAJO_LOCAL WHERE ubicacion = 9901")
        connection.executemany(
            """
            INSERT INTO ORDENES_TRABAJO_LOCAL
              (odt, fecha, hora, equipo, ubicacion, code_conjunto, vibracion,
               temperatura, alineacion, lubricacion, coupling_rpl, correa_ajt,
               reemplazo, sincronizado)
            VALUES (?, ?, ?, ?, 9901, 501, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
            [
                (9901003, '2026-08-04', '10:45:00', 'BOMBA DE AGUA INDUSTRIAL', 1, 1, 1, 1, 1, 0, 1),
                (9901002, '2026-08-03', '14:30:00', 'BOMBA DE AGUA INDUSTRIAL', 1, 1, 1, 1, 0, 0, 0),
                (9901001, '2026-08-02', '09:15:00', 'BOMBA DE AGUA INDUSTRIAL', 1, 1, 0, 1, 0, 0, 0),
            ],
        )
        connection.commit()
    finally:
        connection.close()


def push_database(adb: str, source: str) -> None:
    remote = "/data/local/tmp/scv_ptbg_visual_review.db"
    subprocess.run([adb, "push", source, remote], check=True)
    subprocess.run([adb, "shell", "chmod", "644", remote], check=True)
    subprocess.run(
        [
            adb,
            "shell",
            "run-as",
            "com.example.scv_ptbg",
            "cp",
            remote,
            "databases/scv_ptbg.db",
        ],
        check=True,
    )


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--pull":
        pull_database(sys.argv[2], sys.argv[3])
        main(sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "--seed-push":
        seed_database(sys.argv[3])
        push_database(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "--push":
        push_database(sys.argv[2], sys.argv[3])
    else:
        main(sys.argv[1])
