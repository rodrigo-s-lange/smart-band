from __future__ import annotations

import hmac
import os

import streamlit as st


def require_authentication() -> None:
    if os.getenv("SMARTBAND_DEMO_ALLOW_NO_AUTH", "").lower() == "true":
        st.caption("Modo local de desenvolvimento — autenticação desativada")
        return

    expected = os.getenv("SMARTBAND_DEMO_PASSWORD")
    if not expected:
        st.error("SMARTBAND_DEMO_PASSWORD não foi configurada.")
        st.stop()

    if st.session_state.get("demo_authenticated"):
        return

    st.title("Smart-Band")
    with st.form("login"):
        supplied = st.text_input("Senha temporária", type="password")
        submitted = st.form_submit_button("Entrar", use_container_width=True)
    if submitted and hmac.compare_digest(supplied.encode(), expected.encode()):
        st.session_state["demo_authenticated"] = True
        st.rerun()
    if submitted:
        st.error("Senha inválida.")
    st.stop()

