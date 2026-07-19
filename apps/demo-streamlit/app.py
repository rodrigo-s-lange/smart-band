from __future__ import annotations

import os
from pathlib import Path

import streamlit as st

from demo_app.auth import require_authentication
from demo_app.state import DemoStore
from demo_app.views import (
    alerts_page,
    apply_theme,
    attendance_page,
    control_page,
    devices_page,
    operation_page,
    overview_page,
)


st.set_page_config(
    page_title="Smart-Band · VRPlay Demo",
    page_icon="⌁",
    layout="wide",
    initial_sidebar_state="collapsed",
)
apply_theme()
require_authentication()


@st.cache_resource
def get_store() -> DemoStore:
    default_path = Path(__file__).resolve().parent / "data" / "demo.sqlite3"
    return DemoStore(Path(os.getenv("SMARTBAND_DEMO_DB", default_path)))


store = get_store()

pages = [
    st.Page(
        lambda: overview_page(store), title="Visão Geral", icon=":material/dashboard:",
        url_path="visao-geral",
    ),
    st.Page(
        lambda: attendance_page(store), title="Atendimento",
        icon=":material/point_of_sale:", url_path="atendimento", default=True,
    ),
    st.Page(
        lambda: operation_page(store), title="Operação", icon=":material/attractions:",
        url_path="operacao",
    ),
    st.Page(
        lambda: devices_page(store), title="Dispositivos", icon=":material/devices:",
        url_path="dispositivos",
    ),
    st.Page(
        lambda: alerts_page(store), title="Alertas",
        icon=":material/notification_important:", url_path="alertas",
    ),
    st.Page(
        lambda: control_page(store), title="Controle da Demo", icon=":material/tune:",
        url_path="controle",
    ),
]

navigation = st.navigation(pages, position="top")
navigation.run()
