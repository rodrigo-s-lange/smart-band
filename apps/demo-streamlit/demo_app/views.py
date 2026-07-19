from __future__ import annotations

from datetime import date
from typing import Callable

import pandas as pd
import streamlit as st

from demo_app.state import DemoStore


STATUS_LABELS = {
    "available": "Disponível",
    "linked": "Vinculada",
    "requesting": "Solicitando acesso",
    "awaiting_confirmation": "Aguardando confirmação",
    "confirmed": "Crédito reservado",
    "completed": "Concluída",
    "cancelled": "Cancelada",
    "actuation_failed": "Não executada",
    "reconciliation_required": "Reconciliação necessária",
}


def apply_theme() -> None:
    st.markdown(
        """
        <style>
        .stApp { background: #07111f; color: #e8eef7; }
        [data-testid="stHeader"] { background: rgba(7,17,31,.88); }
        [data-testid="stDecoration"], [data-testid="stAppDeployButton"], #MainMenu, footer {
            visibility: hidden;
        }
        [data-testid="stAppViewBlockContainer"] { padding-top: 1.25rem; max-width: 1500px; }
        .demo-banner {
            display:flex; justify-content:space-between; align-items:center;
            padding:.62rem .9rem; border:1px solid #24405f; border-radius:12px;
            background:linear-gradient(90deg,#0c2038,#102a45); margin-bottom:1rem;
        }
        .demo-badge { color:#07111f; background:#ffd166; border-radius:999px;
            padding:.25rem .65rem; font-weight:800; letter-spacing:.04em; }
        .device-card { border:1px solid #294968; border-radius:18px; padding:1rem;
            background:linear-gradient(145deg,#0b1b2d,#0d243b); margin-bottom:.85rem;
            box-shadow:0 12px 30px rgba(0,0,0,.2); }
        .device-title { font-size:.76rem; letter-spacing:.12em; text-transform:uppercase;
            color:#8eacc9; margin-bottom:.4rem; }
        .oled { background:#02080d; color:#79c8ff; border:2px solid #315b7d;
            border-radius:10px; text-align:center; padding:.9rem .35rem;
            font-family:monospace; font-weight:800; font-size:1.65rem; letter-spacing:.08em; }
        .oled-small { font-size:.88rem; color:#bce3ff; margin-top:.35rem; }
        .status-row { display:flex; justify-content:space-between; gap:.5rem;
            margin-top:.7rem; color:#c6d7e8; font-size:.86rem; }
        .queue-code { font-family:monospace; font-weight:800; font-size:1.1rem;
            padding:.42rem .62rem; margin:.28rem 0; border-radius:8px;
            background:#102d49; border-left:4px solid #35a7ff; }
        .concept { border-left:4px solid #ffd166; background:#302917;
            padding:.7rem .9rem; border-radius:8px; color:#ffe7a5; }
        .success-panel { border-left:4px solid #25c2a0; background:#0d302c;
            padding:.75rem .9rem; border-radius:8px; }
        .muted { color:#8ea5ba; font-size:.84rem; }
        div[data-testid="stMetric"] { background:#0d2034; border:1px solid #203e5b;
            padding:.75rem; border-radius:12px; }
        .stButton > button { border-radius:9px; font-weight:700; }
        </style>
        """,
        unsafe_allow_html=True,
    )


def format_brl(cents: int) -> str:
    return f"R$ {cents / 100:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


def banner(store: DemoStore) -> None:
    metrics = store.metrics()
    st.markdown(
        f"""
        <div class="demo-banner">
          <div><strong>SMART-BAND · VRPLAY DEMO</strong><br>
          <span class="muted">Evento ativo · operação local</span></div>
          <div>{metrics['gateways_online']}/8 gateways · {metrics['bands_in_use']} pulseiras ·
          {metrics['open_alerts']} alertas</div>
          <div class="demo-badge">AMBIENTE DE SIMULAÇÃO</div>
        </div>
        """,
        unsafe_allow_html=True,
    )


def _active_state(snapshot: dict) -> tuple[dict, dict | None]:
    return snapshot["active_band"], snapshot["active_interaction"]


def render_band(store: DemoStore, snapshot: dict) -> None:
    band, interaction = _active_state(snapshot)
    state = interaction["status"] if interaction else band["status"]
    display = band["code"]
    subtitle = f"Saldo {band['balance']} · Reserva {band['reserved']}"
    if interaction and interaction["status"] == "awaiting_confirmation":
        display = interaction["attraction_name"].upper()
        subtitle = f"1 CRÉDITO · CONFIRME"
    elif interaction and interaction["status"] == "confirmed":
        display = "PROCESSANDO"
        subtitle = "Crédito reservado"
    elif snapshot["interactions"] and snapshot["interactions"][0]["status"] == "completed":
        display = "LIBERADO"
        subtitle = f"Saldo {band['balance']} crédito(s)"
    tamper_label = "SEGURA" if band["tamper_status"] == "secure" else "REMOVIDA"
    st.markdown(
        f"""
        <div class="device-card">
          <div class="device-title">Pulseira virtual · {band['id']}</div>
          <div class="oled">{display}<div class="oled-small">{subtitle}</div></div>
          <div class="status-row"><span>{STATUS_LABELS.get(state, state)}</span>
          <span>🔋 {band['battery']}%</span></div>
          <div class="status-row"><span>Tamper: {tamper_label}</span><span>BLE virtual</span></div>
        </div>
        """,
        unsafe_allow_html=True,
    )
    if band["participant_id"] is None:
        st.info("Cadastre e vincule esta pulseira no Atendimento.")
    elif interaction and interaction["status"] == "awaiting_confirmation":
        confirm, cancel = st.columns(2)
        if confirm.button("✓ Confirmar", key="band_confirm", use_container_width=True):
            store.decide_interaction(interaction["id"], True)
            st.rerun()
        if cancel.button("Cancelar", key="band_cancel", use_container_width=True):
            store.decide_interaction(interaction["id"], False)
            st.rerun()
    elif not interaction:
        if st.button("● PRESSIONAR PULSEIRA", key="press_band", use_container_width=True):
            try:
                store.press_band(band["id"])
                st.rerun()
            except ValueError as error:
                st.warning(str(error))


def render_gateway(store: DemoStore, snapshot: dict) -> None:
    gateways = [gateway for gateway in snapshot["gateways"] if gateway["online"]]
    queue = [item for item in snapshot["interactions"] if item["status"] == "requesting"]
    interaction = snapshot["active_interaction"]
    selected_gateway = gateways[0]
    st.markdown(
        f"""
        <div class="device-card">
          <div class="device-title">Gateway virtual · {selected_gateway['friendly_name']}</div>
          <div class="status-row"><span>Online</span><span>RSSI {selected_gateway['rssi']} dBm</span></div>
          <div class="muted" style="margin-top:.7rem">FILA GLOBAL · NOVOS NO TOPO</div>
          {''.join(f'<div class="queue-code">{item["code"]}</div>' for item in queue[:3]) or '<div class="muted">Nenhuma solicitação</div>'}
        </div>
        """,
        unsafe_allow_html=True,
    )
    if queue:
        labels = {item["id"]: f"{item['code']} · solicitação #{item['id']}" for item in queue}
        interaction_id = st.selectbox(
            "Código verbalizado", list(labels), format_func=labels.get, key="gateway_queue"
        )
        attraction_labels = {
            item["id"]: f"{item['name']} · 1 crédito" for item in snapshot["attractions"]
        }
        attraction_id = st.selectbox(
            "Atração", list(attraction_labels), format_func=attraction_labels.get,
            key="gateway_attraction",
        )
        gateway_labels = {
            item["id"]: item["friendly_name"] for item in gateways if item["attraction_id"] == attraction_id
        }
        if not gateway_labels:
            gateway_labels = {item["id"]: item["friendly_name"] for item in gateways}
        operator_gateway = st.selectbox(
            "Gateway da atração", list(gateway_labels), format_func=gateway_labels.get,
            key="operator_gateway",
        )
        if st.button("Selecionar código", key="claim", use_container_width=True):
            store.claim_interaction(interaction_id, attraction_id, operator_gateway)
            st.rerun()
    elif interaction and interaction["status"] == "confirmed":
        st.success(f"Confirmado: {interaction['attraction_name']}. Escolha o retorno simulado:")
        success, failed = st.columns(2)
        if success.button("Liberar atração", key="actuate_success", use_container_width=True):
            store.actuate(interaction["id"], "succeeded")
            st.rerun()
        if failed.button("Não executou", key="actuate_failed", use_container_width=True):
            store.actuate(interaction["id"], "not_executed")
            st.rerun()
        if st.button("Resultado ambíguo", key="actuate_ambiguous", use_container_width=True):
            store.actuate(interaction["id"], "ambiguous")
            st.rerun()


def render_timeline(snapshot: dict, limit: int = 10) -> None:
    st.subheader("Linha do tempo")
    for event in snapshot["timeline"][:limit]:
        time = event["created_at"][11:19]
        st.markdown(f"**{time} · {event['title']}**  \n{event['detail']}")


def render_shell(store: DemoStore, content: Callable[[DemoStore, dict], None]) -> None:
    banner(store)
    snapshot = store.snapshot()
    devices, appliance = st.columns([0.34, 0.66], gap="large")
    with devices:
        render_band(store, snapshot)
        render_gateway(store, snapshot)
    with appliance:
        content(store, snapshot)


def overview_page(store: DemoStore) -> None:
    def content(current_store: DemoStore, snapshot: dict) -> None:
        st.title("Visão Geral")
        metrics = current_store.metrics()
        columns = st.columns(4)
        columns[0].metric("Receita simulada", format_brl(metrics["revenue_cents"]))
        columns[1].metric("Créditos carregados", metrics["credits_loaded"])
        columns[2].metric("Créditos consumidos", metrics["credits_consumed"])
        columns[3].metric("Alertas abertos", metrics["open_alerts"])
        completed = [item for item in snapshot["interactions"] if item["status"] == "completed"]
        usage = {attraction["name"]: 0 for attraction in snapshot["attractions"]}
        for item in completed:
            usage[item["attraction_name"]] += 1
        chart = pd.DataFrame({"Atração": list(usage), "Utilizações": list(usage.values())})
        st.subheader("Utilização por atração")
        st.bar_chart(chart, x="Atração", y="Utilizações", color="#35A7FF")
        render_timeline(snapshot, 8)

    render_shell(store, content)


def attendance_page(store: DemoStore) -> None:
    def content(current_store: DemoStore, snapshot: dict) -> None:
        st.title("Atendimento")
        st.caption("Cadastro e pagamento exclusivamente fictícios")
        band = snapshot["active_band"]
        if band["participant_id"] is None:
            st.subheader("1. Cadastrar e vincular")
            available = [item for item in snapshot["bands"] if item["status"] == "available"]
            with st.form("registration"):
                first, second = st.columns(2)
                with first:
                    name = st.text_input("Nome", value="João Demo")
                    contact = st.text_input("Celular ou e-mail", value="(00) 90000-0000")
                with second:
                    birth_date = st.date_input("Data de nascimento", value=date(2000, 1, 1))
                    band_labels = {item["id"]: item["code"] for item in available}
                    band_id = st.selectbox("Pulseira", list(band_labels), format_func=band_labels.get)
                minor = st.checkbox("Participante menor de idade")
                guardian_columns = st.columns(3)
                with guardian_columns[0]:
                    guardian_name = st.text_input("Responsável", disabled=not minor)
                with guardian_columns[1]:
                    guardian_relationship = st.text_input("Parentesco", disabled=not minor)
                with guardian_columns[2]:
                    guardian_contact = st.text_input("Contato do responsável", disabled=not minor)
                consent, marketing_column = st.columns(2)
                with consent:
                    st.checkbox("Aceite operacional fictício", value=True, disabled=True)
                with marketing_column:
                    marketing = st.checkbox("Marketing fictício e opcional")
                submitted = st.form_submit_button("Cadastrar e vincular", use_container_width=True)
            if submitted:
                try:
                    current_store.register_participant(
                        name=name,
                        birth_date=birth_date.isoformat(),
                        contact=contact,
                        band_id=band_id,
                        guardian_name=guardian_name,
                        guardian_relationship=guardian_relationship,
                        guardian_contact=guardian_contact,
                        marketing_consent=marketing,
                    )
                    st.rerun()
                except ValueError as error:
                    st.error(str(error))
            return

        st.markdown(
            f"<div class='success-panel'><strong>{band['participant_name']}</strong> · Pulseira {band['code']} · Saldo {band['balance']}</div>",
            unsafe_allow_html=True,
        )
        pending = next(
            (sale for sale in snapshot["sales"] if sale["status"] == "pending"), None
        )
        if pending:
            st.subheader("2. Confirmar pagamento")
            st.warning(
                f"Venda #{pending['id']}: {pending['credits']} crédito(s) · "
                f"{format_brl(pending['credits'] * pending['unit_price_cents'])} · "
                f"{pending['payment_method']}"
            )
            confirm, cancel = st.columns(2)
            if confirm.button("Confirmar pagamento", use_container_width=True):
                current_store.confirm_sale(pending["id"])
                st.rerun()
            if cancel.button("Cancelar venda", use_container_width=True):
                current_store.cancel_sale(pending["id"])
                st.rerun()
            return

        st.subheader("2. Carregar créditos")
        with st.form("sale"):
            credits = st.radio("Quantidade", [1, 3, 5, 10], horizontal=True, index=2)
            custom = st.number_input("Quantidade personalizada", min_value=0, max_value=100, value=0)
            if custom:
                credits = int(custom)
            payment = st.radio(
                "Forma de pagamento", ["Crédito", "Débito", "Pix", "Dinheiro"],
                horizontal=True,
            )
            st.metric("Total demonstrativo", format_brl(credits * 2000))
            submitted = st.form_submit_button("Registrar pagamento pendente", use_container_width=True)
        if submitted:
            try:
                current_store.create_sale(
                    band_id=band["id"], credits=int(credits), payment_method=payment
                )
                st.rerun()
            except ValueError as error:
                st.error(str(error))

    render_shell(store, content)


def operation_page(store: DemoStore) -> None:
    def content(_: DemoStore, snapshot: dict) -> None:
        st.title("Operação")
        interaction = snapshot["active_interaction"]
        if interaction:
            st.subheader(f"Interação #{interaction['id']} · {interaction['code']}")
            st.write(f"**Estado:** {STATUS_LABELS.get(interaction['status'], interaction['status'])}")
            st.write(f"**Atração:** {interaction['attraction_name'] or 'Ainda não selecionada'}")
            st.write(f"**Gateway operador:** {interaction['operator_gateway_name'] or '—'}")
            st.write(f"**Gateway de rádio:** {interaction['radio_gateway_name'] or '—'}")
            st.write(f"**Tentativa de rádio:** {interaction['radio_attempt']}")
        else:
            st.info("Nenhuma interação ativa. Pressione a pulseira virtual para começar.")
        terminal = [
            item for item in snapshot["interactions"]
            if item["status"] not in {"requesting", "awaiting_confirmation", "confirmed"}
        ]
        if terminal:
            st.subheader("Último resultado")
            last = terminal[0]
            st.write(
                f"{last['code']} · {STATUS_LABELS.get(last['status'], last['status'])} · "
                f"{last['attraction_name'] or 'sem atração'}"
            )
        render_timeline(snapshot, 12)

    render_shell(store, content)


def devices_page(store: DemoStore) -> None:
    def content(_: DemoStore, snapshot: dict) -> None:
        st.title("Dispositivos")
        gateways_tab, bands_tab = st.tabs(["Gateways", "Pulseiras"])
        with gateways_tab:
            data = pd.DataFrame(snapshot["gateways"])[
                ["friendly_name", "attraction_name", "online", "rssi", "capability"]
            ].rename(columns={
                "friendly_name": "Nome", "attraction_name": "Atração",
                "online": "Online", "rssi": "RSSI", "capability": "Capacidade",
            })
            st.dataframe(data, hide_index=True, use_container_width=True)
        with bands_tab:
            data = pd.DataFrame(snapshot["bands"])[
                ["code", "status", "participant_name", "balance", "battery", "tamper_status"]
            ].rename(columns={
                "code": "Código", "status": "Estado", "participant_name": "Participante",
                "balance": "Saldo", "battery": "Bateria", "tamper_status": "Tamper",
            })
            st.dataframe(data, hide_index=True, use_container_width=True)

    render_shell(store, content)


def alerts_page(store: DemoStore) -> None:
    def content(current_store: DemoStore, snapshot: dict) -> None:
        st.title("Alertas")
        st.markdown(
            "<div class='concept'><strong>Conceito simulado:</strong> tamper não representa sensor físico implementado.</div>",
            unsafe_allow_html=True,
        )
        open_alerts = [item for item in snapshot["alerts"] if item["status"] != "resolved"]
        if not open_alerts:
            st.success("Nenhum alerta aberto.")
        for alert in open_alerts:
            with st.container(border=True):
                st.write(f"**{alert['severity'].upper()} · {alert['kind']} · {alert['status']}**")
                st.write(alert["message"])
                acknowledge, resolve = st.columns(2)
                if acknowledge.button(
                    "Reconhecer", key=f"ack_{alert['id']}", use_container_width=True,
                    disabled=alert["status"] == "acknowledged",
                ):
                    current_store.update_alert(alert["id"], "acknowledged")
                    st.rerun()
                if resolve.button(
                    "Resolver", key=f"resolve_{alert['id']}", use_container_width=True
                ):
                    current_store.update_alert(alert["id"], "resolved")
                    st.rerun()
        render_timeline(snapshot, 8)

    render_shell(store, content)


def control_page(store: DemoStore) -> None:
    def content(current_store: DemoStore, snapshot: dict) -> None:
        st.title("Controle da Demo")
        st.warning("Controles internos — todas as ações afetam somente dados fictícios.")
        st.subheader("Cenário")
        if st.button("Restaurar fixture VRPlay Demo", type="primary", use_container_width=True):
            current_store.reset()
            st.rerun()
        band = snapshot["active_band"]
        interaction = snapshot["active_interaction"]
        left, right = st.columns(2)
        with left:
            if st.button("Simular pulseira removida", use_container_width=True):
                current_store.set_tamper(band["id"], True)
                st.rerun()
            if st.button("Simular pulseira recolocada", use_container_width=True):
                current_store.set_tamper(band["id"], False)
                st.rerun()
        with right:
            if st.button("Gateway Corrida offline/online", use_container_width=True):
                gateway = next(item for item in snapshot["gateways"] if item["id"] == "G1")
                current_store.set_gateway_online("G1", not bool(gateway["online"]))
                st.rerun()
            if st.button(
                "Executar fallback de rádio",
                use_container_width=True,
                disabled=interaction is None,
            ):
                if interaction and current_store.simulate_radio_fallback(interaction["id"]):
                    st.rerun()
                st.warning("Crie uma solicitação antes de executar o fallback.")
        st.subheader("Legenda de maturidade")
        st.markdown(
            """
            - **Vigente:** invariantes e contratos já validados no projeto.
            - **Simulado:** comportamento controlado desta aplicação comercial.
            - **Conceito:** hipótese de produto ainda dependente de decisão ou hardware.
            """
        )
        render_timeline(snapshot, 12)

    render_shell(store, content)
