import 'package:flutter_test/flutter_test.dart';
import 'package:scv_ptbg/models/sesion.dart';

void main() {
  group('quien es administrador', () {
    test('Daniel Berrueta lo es por nombre, sin importar su cargo', () {
      expect(Sesion.esUsuarioAdmin('DANIEL BERRUETA', 'SUP.MECANICO'), isTrue);
      expect(Sesion.esUsuarioAdmin('daniel berrueta', null), isTrue);
      expect(Sesion.esUsuarioAdmin('  Daniel Berrueta ', ''), isTrue);
    });

    test('el usuario generico admin sigue siendo admin', () {
      expect(Sesion.esUsuarioAdmin('admin', 'ADMIN'), isTrue);
    });

    test('un cargo con ADMIN basta: la planta puede nombrar otro sin APK', () {
      expect(Sesion.esUsuarioAdmin('PEDRO PEREZ', 'ADMINISTRADOR'), isTrue);
    });

    test('un mecanico no es admin', () {
      expect(Sesion.esUsuarioAdmin('ALEXI AVILA', 'SUP.MECANICO'), isFalse);
      expect(Sesion.esUsuarioAdmin('PEDRO', 'MECANICO'), isFalse);
      expect(Sesion.esUsuarioAdmin(null, null), isFalse);
    });
  });

  group('resumen de cambios para la bitacora', () {
    test('lista solo lo que cambio, con antes y despues', () {
      final resumen = resumenCambios(
        {'T1': 61.0, 'T2': 88.0, 'obs': 'RUIDO'},
        {'T1': 61.0, 'T2': 90.5, 'obs': 'SIN NOVEDAD'},
      );
      expect(resumen, 'T2: 88.0 → 90.5 · obs: RUIDO → SIN NOVEDAD');
    });

    test('sin cambios devuelve vacio y el evento no se registra', () {
      expect(resumenCambios({'T1': 61.0}, {'T1': 61.0}), isEmpty);
    });

    test('lo vacio y lo nulo se muestran como raya', () {
      expect(resumenCambios({'obs': null}, {'obs': 'AHORA SI'}),
          'obs: — → AHORA SI');
      expect(resumenCambios({'odt': 4521}, {'odt': null}), 'odt: 4521 → —');
    });
  });

  group('el ROL de MDB_USERS manda', () {
    test('DANIEL BERRUETA entra por ROL aunque su cargo no diga ADMIN', () {
      // Asi esta la planta: CARGO 'COORD.MECANICO', ROL 'ADMIN'. Si solo se
      // mirara el cargo, el administrador entraria como un mecanico mas.
      expect(
        Sesion.esUsuarioAdmin('DANIEL BERRUETA', 'COORD.MECANICO', rol: 'ADMIN'),
        isTrue,
      );
    });

    test('nombrar otro administrador es poner ROL=ADMIN, sin tocar la app', () {
      expect(
        Sesion.esUsuarioAdmin('JOSE SANCHEZ', 'SUP.MECANICO', rol: 'ADMIN'),
        isTrue,
      );
      expect(
        Sesion.esUsuarioAdmin('JOSE SANCHEZ', 'SUP.MECANICO', rol: 'admin'),
        isTrue,
      );
    });

    test("ROL 'USUARIO' NO es admin, aunque el cargo suene importante", () {
      expect(
        Sesion.esUsuarioAdmin('CARLOS PARRA', 'SUP.MECANICO', rol: 'USUARIO'),
        isFalse,
      );
      expect(
        Sesion.esUsuarioAdmin('ALEXI AVILA', 'COORD.MECANICO', rol: 'USUARIO'),
        isFalse,
      );
    });

    test('sin ROL (tablet sin descargar) el respaldo por nombre lo rescata', () {
      // Una tablet recien instalada aun no bajo MDB_USERS: el rol llega
      // vacio y Daniel tiene que poder entrar igual.
      expect(Sesion.esUsuarioAdmin('DANIEL BERRUETA', 'COORD.MECANICO'),
          isTrue);
      expect(
        Sesion.esUsuarioAdmin('DANIEL BERRUETA', 'COORD.MECANICO', rol: ''),
        isTrue,
      );
      // Pero un mecanico sin rol sigue siendo mecanico.
      expect(Sesion.esUsuarioAdmin('CARLOS PARRA', 'SUP.MECANICO', rol: ''),
          isFalse);
    });
  });

  group('quien es administrador (casos adversarios)', () {
    test("el cargo 'administrador' en minusculas tambien da rol de admin", () {
      // La comparacion sube todo a mayusculas antes de buscar ADMIN, asi que
      // da igual como haya quedado tecleado el cargo en USUARIOS.
      expect(Sesion.esUsuarioAdmin('PEDRO PEREZ', 'administrador'), isTrue);
      expect(Sesion.esUsuarioAdmin('PEDRO PEREZ', 'Administrador de planta'),
          isTrue);
    });

    test('un espacio doble en el nombre NO se reconoce como Daniel Berrueta',
        () {
      // COMPORTAMIENTO DOCUMENTADO: la lista de administradores compara el
      // nombre exacto (solo recorta extremos y sube a mayusculas). Un doble
      // espacio interno —'DANIEL  BERRUETA'— no coincide y NO es admin por
      // nombre. En la practica no muerde: el nombre viene de la tabla
      // USUARIOS, no de un teclado; y si el cargo trae ADMIN, entra igual.
      expect(Sesion.esUsuarioAdmin('DANIEL  BERRUETA', 'SUP.MECANICO'),
          isFalse);
      // La segunda puerta (el cargo) lo rescata aunque el nombre no calce.
      expect(Sesion.esUsuarioAdmin('DANIEL  BERRUETA', 'ADMINISTRADOR'),
          isTrue);
    });

    test('usuario null con cargo null no lanza y no es admin', () {
      expect(Sesion.esUsuarioAdmin(null, null), isFalse);
      // Y las combinaciones sueltas de null tampoco.
      expect(Sesion.esUsuarioAdmin(null, 'MECANICO'), isFalse);
      expect(Sesion.esUsuarioAdmin('PEDRO', null), isFalse);
    });
  });

  group('la bitacora de una edicion de fecha', () {
    test('deja dicha la fecha vieja y la nueva', () {
      // Lo que el administrador tiene que poder demostrar despues: que la
      // medicion se capturo con una fecha y el la corrigio a otra.
      final resumen = resumenCambios(
        {'fecha': '2026-08-25 08:15:07', 'T1': 61.0},
        {'fecha': '2026-06-02 08:15:07', 'T1': 61.0},
      );
      expect(resumen,
          'fecha: 2026-08-25 08:15:07 → 2026-06-02 08:15:07');
    });

    test('si solo cambio la hora, tambien se ve', () {
      expect(
        resumenCambios(
          {'fecha': '2026-08-25 08:15:07'},
          {'fecha': '2026-08-25 14:30:00'},
        ),
        'fecha: 2026-08-25 08:15:07 → 2026-08-25 14:30:00',
      );
    });

    test('sin tocar la fecha no ensucia la bitacora', () {
      expect(
        resumenCambios(
          {'fecha': '2026-08-25 08:15:07', 'T1': 61.0},
          {'fecha': '2026-08-25 08:15:07', 'T1': 61.0},
        ),
        isEmpty,
      );
    });
  });

  group('resumen de cambios (casos adversarios)', () {
    test('una clave que estaba antes pero ya no viene despues SE IGNORA', () {
      // COMPORTAMIENTO DOCUMENTADO: el resumen recorre solo las claves de
      // "despues". Si el mapa nuevo ni siquiera trae la columna, el diff no
      // la ve y no la reporta como borrada. Los editores siempre arman los
      // dos mapas con las mismas claves, asi que hoy no muerde; pero si un
      // editor futuro omite una clave, ese cambio no quedaria en bitacora.
      expect(resumenCambios({'T1': 61.0, 'obs': 'RUIDO'}, {'T1': 61.0}),
          isEmpty);
    });

    test('61.0 (double) contra 61 (int) SI se reporta: falso positivo', () {
      // COMPORTAMIENTO DOCUMENTADO: la comparacion es sobre el texto plano y
      // '61.0' != '61', asi que un mismo valor guardado como double y releido
      // como int aparece en la bitacora como "cambio" ('T1: 61.0 → 61').
      // Ruido inofensivo (una linea de mas en EVENTOS_ADMIN, nunca datos
      // corruptos) y solo posible si los tipos difieren entre lecturas.
      expect(resumenCambios({'T1': 61.0}, {'T1': 61}), 'T1: 61.0 → 61');
    });

    test("el texto 'null' literal se trata igual que un null de verdad", () {
      // SQLite a veces devuelve la cadena 'null' cuando una columna paso por
      // un toString() descuidado; plano() la aplana a raya como al null real.
      expect(resumenCambios({'obs': 'null'}, {'obs': null}), isEmpty);
      expect(resumenCambios({'obs': 'NULL'}, {'obs': 'AHORA SI'}),
          'obs: — → AHORA SI');
    });

    test('con ambos mapas vacios devuelve vacio, sin lanzar', () {
      expect(resumenCambios({}, {}), isEmpty);
    });
  });
}
