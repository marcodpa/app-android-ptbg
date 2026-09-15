"""Inicia el subidor USB solicitando la clave de MariaDB de forma local."""

import tkinter as tk
from tkinter import messagebox, simpledialog

import tablet_uploader as uploader


def request_credentials() -> bool:
    prompt = tk.Tk()
    prompt.withdraw()
    prompt.attributes("-topmost", True)
    try:
        user = uploader.DB_USER or "admin"
        while True:
            entered_user = simpledialog.askstring(
                "SCV-PTBG · MariaDB",
                "Usuario de MariaDB:",
                initialvalue=user,
                parent=prompt,
            )
            if not entered_user:
                return False
            user = entered_user.strip()
            password = simpledialog.askstring(
                "SCV-PTBG · MariaDB",
                "Contraseña de MariaDB:",
                show="●",
                parent=prompt,
            )
            if password is None:
                return False

            uploader.DB_USER = user
            uploader.DB_PASS = password
            try:
                connection = uploader.connect_mariadb()
                connection.close()
            except Exception as exc:
                retry = messagebox.askretrycancel(
                    "SCV-PTBG · MariaDB",
                    f"No se pudo conectar.\n\n{exc}\n\n"
                    "Presione Reintentar para corregir los datos.",
                    parent=prompt,
                )
                if retry:
                    continue
                return False
            messagebox.showinfo(
                "SCV-PTBG · MariaDB",
                "Conexión correcta. La clave permanecerá solamente en memoria.",
                parent=prompt,
            )
            return True
    finally:
        prompt.destroy()


if __name__ == "__main__":
    instance_lock = uploader.acquire_gui_instance_lock()
    if instance_lock is not None and request_credentials():
        uploader.launch_gui()
