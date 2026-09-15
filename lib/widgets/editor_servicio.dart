import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Un valor que se puede corregir.
///
/// [clave] es la columna donde vive el dato (`T1`, `H2`, `L3`...). No se
/// muestra: lo que ve el tecnico es [etiqueta].
class CampoServicio {
  const CampoServicio({
    required this.clave,
    required this.etiqueta,
    required this.valor,
  });

  final String clave;

  /// Como se llama en el campo: "Horizontal", "Temperatura", "Gramos".
  final String etiqueta;

  final double? valor;
}

/// Un punto del equipo con lo que se le midio.
///
/// La vibracion mide tres ejes en cada punto, y la temperatura y la
/// lubricacion uno solo; los dos casos entran aqui.
class PuntoServicio {
  const PuntoServicio({required this.nombre, required this.campos});

  /// El nombre real del punto: "Motor - lado acople".
  ///
  /// Antes cada campo decia "Punto 1", "Punto 2". El tecnico que abre esto
  /// para corregir un numero mal tecleado no tiene como saber cual de los
  /// cuatro puntos del equipo es el 3, y terminaba corrigiendo el que no era.
  final String nombre;

  final List<CampoServicio> campos;
}

/// Lo que devuelve el editor cuando se guarda.
class EdicionServicio {
  const EdicionServicio({
    required this.valores,
    required this.observaciones,
    required this.responsable,
    required this.cargo,
    required this.odt,
    required this.fecha,
    required this.hora,
  });

  final Map<String, double?> valores;
  final String observaciones;
  final String responsable;
  final String cargo;
  final int? odt;

  /// Cuando se hizo la medicion, en el formato de la base (yyyy-MM-dd y
  /// HH:mm:ss). Corregirla es cosa del administrador: una medicion capturada
  /// con la fecha equivocada desordena el historial de ese equipo.
  final String fecha;
  final String hora;
}

/// Abre el editor de un servicio ya capturado y devuelve los cambios.
///
/// Es el mismo para vibracion, temperatura y lubricacion. Antes cada uno
/// tenia su propia pantalla —dos hojas distintas y un dialogo— y cada una
/// mostraba cosas diferentes: unas dejaban tocar las observaciones y ninguna
/// dejaba corregir quien lo hizo, su cargo ni la orden de trabajo, que es
/// justo lo que mas se equivoca al capturar con prisa.
Future<EdicionServicio?> editarServicio(
  BuildContext context, {
  required IconData icono,
  required String titulo,
  required String subtitulo,
  required String unidad,
  required List<PuntoServicio> puntos,
  required String observaciones,
  required String responsable,
  required String cargo,
  required int? odt,
  required String fecha,
  required String hora,
}) {
  return showModalBottomSheet<EdicionServicio>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditorServicio(
      icono: icono,
      titulo: titulo,
      subtitulo: subtitulo,
      unidad: unidad,
      puntos: puntos,
      observaciones: observaciones,
      responsable: responsable,
      cargo: cargo,
      odt: odt,
      fecha: fecha,
      hora: hora,
    ),
  );
}

/// La cascara comun de los editores: cabecera, cuerpo y botones.
///
/// Se saco aparte para que el editor de servicios y el de reemplazos sean
/// literalmente la misma hoja y no dos cosas parecidas. Antes el de
/// reemplazos era un AlertDialog con estilo claro en medio de una app
/// oscura, y no se parecia a nada del resto.
class HojaEditor extends StatelessWidget {
  const HojaEditor({
    super.key,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.hijos,
    required this.onGuardar,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final List<Widget> hijos;
  final VoidCallback onGuardar;

  @override
  Widget build(BuildContext context) {
    final oscuro = esterThemeController.isDark;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            color: oscuro ? AppColors.surface : Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.shadowLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icono, size: 19, color: AppColors.teal),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(titulo,
                            style: AppText.titulo.copyWith(
                                color: oscuro
                                    ? AppColors.textPrimary
                                    : AppColors.headerTop),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (subtitulo.isNotEmpty)
                          Text(subtitulo,
                              style: AppText.apoyo
                                  .copyWith(color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar sin guardar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ]),
              ),
              const Divider(height: 1, color: AppColors.border),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  shrinkWrap: true,
                  children: hijos,
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCELAR'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onGuardar,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('GUARDAR'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Titulo de seccion dentro de una [HojaEditor].
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto.toUpperCase(),
        style: AppText.micro.copyWith(
          color: AppColors.teal,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      );
}

class _EditorServicio extends StatefulWidget {
  const _EditorServicio({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.unidad,
    required this.puntos,
    required this.observaciones,
    required this.responsable,
    required this.cargo,
    required this.odt,
    required this.fecha,
    required this.hora,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final String unidad;
  final List<PuntoServicio> puntos;
  final String observaciones;
  final String responsable;
  final String cargo;
  final int? odt;
  final String fecha;
  final String hora;

  @override
  State<_EditorServicio> createState() => _EditorServicioState();
}

class _EditorServicioState extends State<_EditorServicio> {
  late final Map<String, TextEditingController> _valores;
  late final TextEditingController _observaciones;
  late final TextEditingController _responsable;
  late final TextEditingController _cargo;
  late final TextEditingController _odt;
  /// La fecha y la hora de la medicion, tal como van a la base.
  late String _fecha;
  late String _hora;

  @override
  void initState() {
    super.initState();
    _valores = {
      for (final punto in widget.puntos)
        for (final campo in punto.campos)
          campo.clave: TextEditingController(text: _texto(campo.valor)),
    };
    _observaciones = TextEditingController(text: widget.observaciones);
    _responsable = TextEditingController(text: widget.responsable);
    _cargo = TextEditingController(text: widget.cargo);
    _odt = TextEditingController(text: widget.odt?.toString() ?? '');
    _fecha = widget.fecha;
    _hora = widget.hora;
  }

  /// El valor tal como se escribio, sin decimales de relleno.
  ///
  /// Antes se formateaba a dos decimales siempre, asi que abrir el editor y
  /// guardar sin tocar nada convertia un 5 en 5.00. No cambia la medicion,
  /// pero el historial mostraba una edicion donde no hubo ninguna.
  static String _texto(double? valor) {
    if (valor == null) return '';
    if (valor == valor.roundToDouble()) return valor.toInt().toString();
    return valor.toString();
  }

  @override
  void dispose() {
    for (final c in _valores.values) {
      c.dispose();
    }
    _observaciones.dispose();
    _responsable.dispose();
    _cargo.dispose();
    _odt.dispose();
    super.dispose();
  }

  void _guardar() {
    Navigator.pop(
      context,
      EdicionServicio(
        valores: {
          for (final entrada in _valores.entries)
            // Una coma decimal se acepta igual que un punto: el teclado
            // numerico de la tablet ofrece la coma y `double.tryParse` la
            // rechaza, asi que un "4,5" se guardaba como vacio y la lectura
            // desaparecia sin avisar.
            entrada.key:
                double.tryParse(entrada.value.text.trim().replaceAll(',', '.')),
        },
        observaciones: _observaciones.text.trim(),
        responsable: _responsable.text.trim(),
        cargo: _cargo.text.trim(),
        odt: int.tryParse(_odt.text.trim()),
        fecha: _fecha,
        hora: _hora,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => HojaEditor(
        icono: widget.icono,
        titulo: widget.titulo,
        subtitulo: widget.subtitulo,
        onGuardar: _guardar,
        hijos: _campos(esterThemeController.isDark),
      );

  List<Widget> _campos(bool oscuro) => [
        const TituloSeccion('Valores medidos'),
        const SizedBox(height: 8),
        for (final punto in widget.puntos) ...[
          _tarjetaPunto(punto, oscuro),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        const TituloSeccion('Quién lo hizo'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            flex: 3,
            child: _campoTexto(_responsable, 'Responsable', mayusculas: true),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _campoTexto(_cargo, 'Cargo', mayusculas: true),
          ),
        ]),
        const SizedBox(height: 10),
        _campoTexto(_odt, 'Orden de trabajo (ODT)', numero: true),
        const SizedBox(height: 18),
        const TituloSeccion('Cuándo se hizo'),
        const SizedBox(height: 8),
        _filaFechaHora(oscuro),
        const SizedBox(height: 18),
        const TituloSeccion('Observaciones'),
        const SizedBox(height: 8),
        _campoTexto(_observaciones, 'Lo que se observó en el equipo',
            lineas: 3),
      ];

  /// Fecha y hora de la medicion, con calendario y reloj.
  ///
  /// Una medicion capturada con la fecha equivocada desordena el historial
  /// del equipo y sale mal en la planilla. Corregirla es potestad del
  /// administrador —solo el llega a este editor— y el cambio queda anotado
  /// en la bitacora con la fecha vieja, la nueva y quien la toco.
  Widget _filaFechaHora(bool oscuro) => Row(children: [
        Expanded(
          child: _botonDato(
            clave: const Key('editor-fecha'),
            icono: Icons.calendar_today_rounded,
            etiqueta: 'Fecha',
            valor: _fecha.isEmpty ? 'Sin fecha' : _fecha,
            oscuro: oscuro,
            onTap: () async {
              final actual = DateTime.tryParse(_fecha) ?? DateTime.now();
              final elegida = await showDatePicker(
                context: context,
                initialDate: actual,
                firstDate: DateTime(actual.year - 10),
                lastDate: DateTime.now(),
                helpText: 'Fecha de la medición',
              );
              if (elegida == null) return;
              setState(() {
                _fecha = '${elegida.year.toString().padLeft(4, '0')}-'
                    '${elegida.month.toString().padLeft(2, '0')}-'
                    '${elegida.day.toString().padLeft(2, '0')}';
              });
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _botonDato(
            clave: const Key('editor-hora'),
            icono: Icons.schedule_rounded,
            etiqueta: 'Hora',
            valor: _hora.isEmpty ? 'Sin hora' : _hora,
            oscuro: oscuro,
            onTap: () async {
              final partes = _hora.split(':');
              final elegida = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: int.tryParse(partes.elementAtOrNull(0) ?? '') ?? 0,
                  minute: int.tryParse(partes.elementAtOrNull(1) ?? '') ?? 0,
                ),
                helpText: 'Hora de la medición',
              );
              if (elegida == null) return;
              setState(() {
                _hora = '${elegida.hour.toString().padLeft(2, '0')}:'
                    '${elegida.minute.toString().padLeft(2, '0')}:00';
              });
            },
          ),
        ),
      ]);

  Widget _botonDato({
    required Key clave,
    required IconData icono,
    required String etiqueta,
    required String valor,
    required bool oscuro,
    required VoidCallback onTap,
  }) =>
      InkWell(
        key: clave,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: oscuro ? AppColors.bg : const Color(0xFFF3F7FC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(icono, size: 17, color: AppColors.teal),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(etiqueta,
                      style: AppText.micro
                          .copyWith(color: AppColors.textSecondary)),
                  Text(valor,
                      style: AppText.cuerpoFuerte
                          .copyWith(color: AppColors.textPrimary)),
                ],
              ),
            ),
          ]),
        ),
      );

  /// Un punto del equipo con sus campos en una fila.
  ///
  /// Se agrupan por punto y no en una lista plana porque la vibracion mide
  /// tres ejes en el mismo sitio: verlos juntos bajo el nombre del punto es
  /// como estan en el papel y como se toman en campo.
  Widget _tarjetaPunto(PuntoServicio punto, bool oscuro) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: oscuro ? AppColors.bg : const Color(0xFFF3F7FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(punto.nombre,
                style: AppText.cuerpoFuerte.copyWith(
                    color:
                        oscuro ? AppColors.textPrimary : AppColors.headerTop)),
            const SizedBox(height: 9),
            Row(
              children: [
                for (var i = 0; i < punto.campos.length; i++) ...[
                  if (i > 0) const SizedBox(width: 9),
                  Expanded(child: _campoValor(punto.campos[i])),
                ],
              ],
            ),
          ],
        ),
      );

  Widget _campoValor(CampoServicio campo) => TextFormField(
        controller: _valores[campo.clave],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        // Solo cifras, punto y coma: en el teclado de la tablet es facil
        // rozar una letra y dejar el valor invalido sin darse cuenta.
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
        ],
        style: AppText.dato,
        decoration: InputDecoration(
          labelText: campo.etiqueta,
          suffixText: widget.unidad,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _campoTexto(
    TextEditingController controlador,
    String etiqueta, {
    int lineas = 1,
    bool numero = false,
    bool mayusculas = false,
  }) =>
      TextFormField(
        controller: controlador,
        maxLines: lineas,
        keyboardType: numero ? TextInputType.number : TextInputType.text,
        textCapitalization: mayusculas
            ? TextCapitalization.characters
            : TextCapitalization.sentences,
        inputFormatters:
            numero ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          labelText: etiqueta,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}
