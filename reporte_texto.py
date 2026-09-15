# -*- coding: utf-8 -*-
"""Texto compartido por los generadores de planillas.

Existe para que las cuatro planillas —equipos rotativos, formato oficial,
compresores y black start— traten el texto igual. Antes cada una lo escribia
tal como venia de la tablet, y en el mismo archivero convivian observaciones
en mayusculas, en minusculas y a media capitalizacion segun como hubiera
escrito el tecnico ese dia.
"""
from __future__ import annotations
from decimal import Decimal, InvalidOperation


def medicion(valor, vacio="") -> str:
    """Solo al imprimir: cero exacto significa no tomado; no redondear lecturas.

    Decimal evita confundir decimales pequenos con cero. No usar para fechas,
    identificadores, observaciones ni respuestas booleanas.
    """
    texto = "" if valor is None else str(valor).strip()
    if not texto:
        return vacio
    try:
        numero = Decimal(texto.replace(",", "."))
        if numero.is_finite() and numero.is_zero():
            return "/"
    except InvalidOperation:
        pass
    return texto


def observacion(valor) -> str:
    """Una observacion como va al papel: en mayusculas.

    Las planillas son documentos controlados y se archivan; que unas digan
    "equipo disponible" y otras "EQUIPO DISPONIBLE" segun el humor de quien
    la lleno hace que el archivo no se vea como un mismo formato.

    Se pasa a mayusculas al imprimir y no al guardar a proposito: en la base
    queda lo que el tecnico escribio, sin alterar. Solo cambia la
    presentacion.

    `str.upper()` de Python respeta los acentos, asi que "alineación" sale
    "ALINEACIÓN" y no "ALINEACION".
    """
    if valor is None:
        return ""
    return str(valor).strip().upper()
