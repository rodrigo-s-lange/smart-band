from __future__ import annotations

from datetime import UTC, date, datetime
from html import escape
import time
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


CLIENT_QUESTION_GROUPS = (
    (
        "Cadastro, privacidade e menores",
        (
            ("1", "Cadastro", "Quais dados são obrigatórios e o uso anônimo será permitido?"),
            ("1.1", "Menores", "Quais dados e confirmações serão exigidos do responsável legal?"),
            ("1.2", "LGPD", "Qual base legal, prazo de retenção e processo de exclusão/exportação serão adotados?"),
        ),
    ),
    (
        "Créditos, venda e pagamento",
        (
            ("2", "Carga de créditos", "A venda será por pacotes, quantidade livre ou ambos?"),
            ("2.1", "Pagamento", "Quais meios serão aceitos e a confirmação será manual ou integrada?"),
            ("2.2", "Validade", "Os créditos valem por visita, dia, evento ou não expiram?"),
            ("2.3", "Exceções", "Como tratar cancelamento, estorno, cortesia, bônus e transferência de saldo?"),
            ("2.4", "Conciliação", "Quais relatórios devem confrontar cartão, Pix e dinheiro em caixa?"),
        ),
    ),
    (
        "Atrações e regras comerciais",
        (
            ("3", "Preço", "Quantos créditos cada atração consome?"),
            ("3.1", "Duração", "O consumo será fixo, por tempo ou combinado por atração?"),
            ("3.2", "Capacidade", "Quais atrações são individuais, em dupla ou em grupo?"),
            ("3.3", "Formação de grupo", "Qual o mínimo de pulseiras e o timeout para formar cada grupo?"),
        ),
    ),
    (
        "Gateway, liberação e encerramento",
        (
            ("4", "Liberação", "Como cada gateway ativa sua atração: LED, relé, catraca, tomada ou protocolo?"),
            ("4.1", "Comprovação", "Qual sinal confirma que a atração realmente foi liberada?"),
            ("4.2", "Estado seguro", "O que o equipamento deve fazer em falha, manutenção ou evacuação?"),
            ("4.3", "Encerramento", "Confirmamos que toda atração deve ser encerrada no gateway, com ou sem tempo?"),
            ("4.4", "Gateway indisponível", "Confirmamos fechamento por outro gateway e reentrada como último recurso?"),
        ),
    ),
    (
        "Tempo e experiência da pulseira",
        (
            ("5", "Início", "Em qual evento o tempo começa: confirmação, liberação ou ack físico?"),
            ("5.1", "Fim do tempo", "O que acontece fisicamente e visualmente quando o contador chega a 00:00?"),
            ("5.2", "Avisos", "Quando e como pulseira, TFT, LED e vibracall devem alertar o término?"),
            ("5.3", "Pausa", "Pausa, manutenção ou falha do brinquedo interrompem o relógio?"),
            ("5.4", "Grupos", "A saída de uma pulseira encerra somente sua participação ou exige outra ação?"),
        ),
    ),
    (
        "Operação, relatórios e continuidade",
        (
            ("6", "Permissões", "Quem pode confirmar vendas, conceder cortesia, ajustar saldo e reconciliar falhas?"),
            ("6.1", "Métricas", "Quais indicadores de venda, uso e duração por atração são prioritários?"),
            ("6.2", "Fechamento", "O fechamento será por turno, dia ou terminal e quem aprova divergências?"),
            ("6.3", "Continuidade", "Quais SLA, backup, UPS, acesso remoto e procedimento offline são necessários?"),
        ),
    ),
    (
        "Diferenciais e próximos módulos",
        (
            ("7", "Vibracall", "O vibracall entra no MVP e em quais alertas?"),
            ("7.1", "Acessibilidade", "Quais mensagens visuais são essenciais para pessoas com deficiência auditiva?"),
            ("7.2", "Pulseira removida", "O sensor tamper entra no MVP e quem recebe o alerta?"),
            ("8", "Gamificação", "Haverá missões, bônus ou sorteios de créditos?"),
            ("8.1", "Ocupação BLE", "Quais métricas de lotação/concentração são úteis e com qual retenção?"),
            ("8.2", "Comissão", "Haverá comissão por venda de créditos e qual será a regra?"),
            ("9", "Campanhas", "O que precisa variar entre eventos: marca, preços, atrações, validade e relatórios?"),
            ("9.1", "Piloto", "Qual escopo, data, responsáveis e critério de sucesso do primeiro piloto?"),
        ),
    ),
)


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
        .band-shell { max-width:480px; margin:0 auto .65rem; background:#101820;
            border:2px solid #263846; border-radius:22px; padding:1rem 1.2rem;
            box-shadow:0 12px 30px rgba(0,0,0,.25); }
        .oled-screen { aspect-ratio:4/1; background:#00040a; color:#56bfff;
            border:2px solid #236b9d; border-radius:7px; display:flex;
            flex-direction:column; align-items:center; justify-content:center;
            font-family:Consolas,monospace; font-weight:900; line-height:1.02;
            text-align:center; text-shadow:0 0 9px rgba(53,167,255,.75); }
        .oled-one { font-size:clamp(1.75rem,3.3vw,2.75rem); letter-spacing:.04em; }
        .oled-two { font-size:clamp(1.18rem,2.35vw,1.8rem); letter-spacing:.02em; }
        .tft-shell { width:min(82%,255px); margin:.8rem auto; background:#141b22;
            border:3px solid #344656; border-radius:17px; padding:.7rem;
            box-shadow:0 16px 34px rgba(0,0,0,.3); }
        .tft-screen { aspect-ratio:170/320; background:#02070d; border-radius:8px;
            border:2px solid #25394a; padding:.8rem .62rem; display:flex;
            flex-direction:column; overflow:hidden; font-family:Consolas,monospace; }
        .tft-attraction { color:#fff; font-size:1.45rem; font-weight:900;
            text-align:center; padding-bottom:.55rem; border-bottom:2px solid #27394a; }
        .tft-status { flex:1; display:flex; align-items:center; justify-content:center;
            text-align:center; font-size:1.72rem; font-weight:900; line-height:1.12; }
        .tft-code { font-size:1.28rem; font-weight:900; padding:.5rem .35rem;
            margin:.24rem 0; border-radius:6px; color:#fff; background:#0d2034; }
        .tft-code.selected { color:#ffd54a; border:2px solid #ffd54a; }
        .tft-timer { text-align:center; font-size:2rem; font-weight:900;
            color:#fff; padding:.55rem 0; }
        .green { color:#39e58c; } .amber { color:#ffd54a; } .red { color:#ff5252; }
        .concept { border-left:4px solid #ffd166; background:#302917;
            padding:.7rem .9rem; border-radius:8px; color:#ffe7a5; }
        .success-panel { border-left:4px solid #25c2a0; background:#0d302c;
            padding:.75rem .9rem; border-radius:8px; }
        .muted { color:#8ea5ba; font-size:.84rem; }
        div[data-testid="stMetric"] { background:#0d2034; border:1px solid #203e5b;
            padding:.75rem; border-radius:12px; }
        .stButton > button { border-radius:9px; font-weight:700; }
        .question-card { border:1px solid #24405f; background:#0b1b2d;
            padding:.72rem .85rem; border-radius:10px; margin:.42rem 0; }
        .question-number { color:#56bfff; font-weight:900; font-size:1.08rem; }
        .question-title { color:#fff; font-weight:800; margin-left:.35rem; }
        .question-text { color:#cbd8e6; margin-top:.28rem; line-height:1.35; }
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
          <div><strong>SMART-BAND · VRPLAY</strong><br>
          <span class="muted">Evento ativo · operação local</span></div>
          <div>{metrics['gateways_online']}/8 gateways · {metrics['bands_in_use']} pulseiras ·
          {metrics['open_alerts']} alertas</div>
        </div>
        """,
        unsafe_allow_html=True,
    )


def format_timer(seconds: int) -> str:
    minutes, remainder = divmod(max(0, seconds), 60)
    return f"{minutes:02d}:{remainder:02d}"


def seconds_since(value: str | None) -> float:
    if not value:
        return 9999
    return (datetime.now(UTC) - datetime.fromisoformat(value)).total_seconds()


def oled(lines: list[str]) -> None:
    content = "".join(f"<div>{escape(line)}</div>" for line in lines)
    size = "oled-one" if len(lines) == 1 else "oled-two"
    st.markdown(
        f'<div class="band-shell"><div class="oled-screen {size}">{content}</div></div>',
        unsafe_allow_html=True,
    )


@st.fragment(run_every="1s")
def render_band(store: DemoStore) -> None:
    snapshot = store.snapshot()
    band = snapshot["active_band"]
    interaction = snapshot["active_interaction"]
    session = snapshot["active_session"]
    latest = snapshot["interactions"][0] if snapshot["interactions"] else None
    now = time.time()
    feedback_kind = st.session_state.get("band_feedback_kind")
    feedback_until = st.session_state.get("band_feedback_until", 0.0)
    if feedback_until <= now:
        feedback_kind = None
        st.session_state.pop("band_feedback_kind", None)
        st.session_state.pop("band_feedback_until", None)

    lines: list[str] = []
    if band["participant_id"] is None:
        lines = []
    elif feedback_kind == "end_prompt":
        lines = ["ENCERRAR", "SESSAO? OK"]
    elif feedback_kind == "balance":
        lines = [
            f"{band['balance']}    {format_timer(session['session_remaining_seconds'])}"
            if session
            else str(band["balance"])
        ]
    elif feedback_kind == "recharge":
        lines = ["IR AO CAIXA", "VRPLAY :)"]
    elif interaction and interaction["status"] == "requesting":
        lines = [interaction["code"]]
    elif interaction and interaction["status"] == "awaiting_confirmation":
        lines = [interaction["attraction_name"].upper(), f"-{interaction['cost_credits']}      OK?"]
    elif interaction and interaction["status"] == "confirmed":
        lines = ["AGUARDE"]
    elif latest and latest["status"] == "completed" and latest["session_started_at"]:
        start_age = seconds_since(latest["session_started_at"])
        end_age = seconds_since(latest["session_ended_at"])
        if latest["session_end_reason"] == "timeout" and end_age < 3:
            lines = ["TEMPO", "ENCERRADO"]
        elif latest["session_end_reason"] == "timeout" and end_age < 6:
            lines = [str(band["balance"])]
        elif latest["session_end_reason"] == "band" and end_age < 3:
            lines = [str(band["balance"])]
        elif not latest["session_ended_at"] and start_age < 3:
            lines = ["LIBERADO"]
        elif not latest["session_ended_at"] and start_age < 6:
            lines = [f"{band['balance']}    {format_timer(latest['session_remaining_seconds'])}"]
    elif latest and latest["status"] == "cancelled" and seconds_since(latest["updated_at"]) < 3:
        lines = ["CANCELADO"]
    elif latest and latest["status"] == "actuation_failed" and seconds_since(latest["updated_at"]) < 3:
        lines = ["ERRO"]

    oled(lines)

    if band["participant_id"] is None:
        return
    if feedback_kind == "end_prompt":
        confirm, back = st.columns(2)
        if confirm.button("OK", key="band_end_ok", use_container_width=True):
            store.end_session(band["id"])
            st.session_state["band_feedback_kind"] = "balance"
            st.session_state["band_feedback_until"] = time.time() + 3
            st.rerun()
        if back.button("Voltar", key="band_end_back", use_container_width=True):
            st.session_state.pop("band_feedback_kind", None)
            st.session_state.pop("band_feedback_until", None)
            st.rerun()
        return
    if interaction and interaction["status"] == "awaiting_confirmation":
        confirm, cancel = st.columns(2)
        if confirm.button("OK", key="band_confirm", use_container_width=True):
            try:
                store.decide_interaction(interaction["id"], True)
            except ValueError:
                st.session_state["band_feedback_kind"] = "recharge"
                st.session_state["band_feedback_until"] = time.time() + 6
            st.rerun()
        if cancel.button("Cancelar", key="band_cancel", use_container_width=True):
            store.decide_interaction(interaction["id"], False)
            st.rerun()
        return
    one, two = st.columns(2)
    if one.button("1 CLIQUE", key="band_single_click", use_container_width=True):
        st.session_state["band_feedback_kind"] = "balance"
        st.session_state["band_feedback_until"] = time.time() + 3
        st.rerun()
    if two.button("2 CLIQUES", key="band_double_click", use_container_width=True):
        if session:
            st.session_state["band_feedback_kind"] = "end_prompt"
            st.session_state["band_feedback_until"] = time.time() + 30
        elif band["balance"] - band["reserved"] < 1:
            st.session_state["band_feedback_kind"] = "recharge"
            st.session_state["band_feedback_until"] = time.time() + 6
        else:
            store.press_band(band["id"])
        st.rerun()


def tft_markup(
    attraction: str,
    *,
    status: str | None = None,
    status_color: str = "",
    timer: str | None = None,
    timer_color: str = "",
    queue: list[dict] | None = None,
    selected_id: int | None = None,
) -> str:
    body = ""
    if timer:
        body += f'<div class="tft-timer {timer_color}">{escape(timer)}</div>'
    if status:
        body += f'<div class="tft-status {status_color}">{escape(status).replace(chr(10), "<br>")}</div>'
    for item in queue or []:
        selected = " selected" if item["id"] == selected_id else ""
        prefix = "&gt; " if selected else "&nbsp;&nbsp;"
        body += f'<div class="tft-code{selected}">{prefix}{escape(item["code"])}</div>'
    return (
        '<div class="tft-shell"><div class="tft-screen">'
        f'<div class="tft-attraction">{escape(attraction.upper())}</div>{body}'
        "</div></div>"
    )


@st.fragment(run_every="1s")
def render_gateway(store: DemoStore) -> None:
    snapshot = store.snapshot()
    gateway = next(item for item in snapshot["gateways"] if item["id"] == "G1")
    attraction = gateway["attraction_name"] or "CORRIDA"
    queue = [item for item in snapshot["interactions"] if item["status"] == "requesting"]
    interaction = snapshot["active_interaction"]
    session = snapshot["active_session"]
    pending_end = snapshot["pending_gateway_end"]
    latest = snapshot["interactions"][0] if snapshot["interactions"] else None
    selected_id = st.session_state.get("gateway_queue")
    queue_ids = {item["id"] for item in queue}
    if selected_id not in queue_ids:
        selected_id = queue[0]["id"] if queue else None

    if not gateway["online"]:
        markup = tft_markup(attraction, status="OFFLINE", status_color="red")
    elif pending_end:
        markup = tft_markup(attraction, status="ENCERRADO", status_color="red")
    elif interaction and interaction["status"] == "reconciliation_required":
        markup = tft_markup(attraction, status="VERIFICAR\nATRACAO", status_color="red")
    elif latest and latest["status"] == "actuation_failed":
        markup = tft_markup(attraction, status="FALHA\nLIBERACAO", status_color="red")
    elif interaction and interaction["status"] == "awaiting_confirmation":
        markup = tft_markup(
            attraction, status=f"{interaction['code']}\n\nPULSEIRA...", status_color="amber"
        )
    elif session:
        remaining = session["session_remaining_seconds"]
        markup = tft_markup(
            attraction,
            timer=format_timer(remaining),
            timer_color="red" if remaining <= 30 else "",
            queue=queue[:3],
            selected_id=selected_id,
        )
    elif interaction and interaction["status"] == "confirmed":
        markup = tft_markup(
            attraction, status="AGUARDE", status_color="amber", queue=queue[:3], selected_id=selected_id
        )
    elif queue:
        markup = tft_markup(attraction, queue=queue[:4], selected_id=selected_id)
    else:
        markup = tft_markup(attraction, status="LIVRE", status_color="green")
    st.markdown(markup, unsafe_allow_html=True)

    if pending_end:
        if st.button("OK · ATRAÇÃO LIVRE", key="gateway_end_ok", use_container_width=True):
            store.acknowledge_session_end(pending_end["id"])
            st.rerun()
        return
    if queue and not session and not (
        interaction and interaction["status"] in {"awaiting_confirmation", "confirmed", "reconciliation_required"}
    ):
        labels = {item["id"]: item["code"] for item in queue}
        interaction_id = st.selectbox(
            "Código", list(labels), format_func=labels.get, key="gateway_queue"
        )
        if st.button("Selecionar código", key="claim", use_container_width=True):
            store.claim_interaction(interaction_id, gateway["attraction_id"], gateway["id"])
            st.rerun()
    if interaction and interaction["status"] == "confirmed":
        success, failed = st.columns(2)
        if success.button("Liberar", key="actuate_success", use_container_width=True):
            store.actuate(interaction["id"], "succeeded")
            st.rerun()
        if failed.button("Falhou", key="actuate_failed", use_container_width=True):
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
        render_band(store)
        render_gateway(store)
    with appliance:
        content(store, snapshot)


def overview_page(store: DemoStore) -> None:
    def content(current_store: DemoStore, snapshot: dict) -> None:
        st.title("Visão Geral")
        metrics = current_store.metrics()
        columns = st.columns(4)
        columns[0].metric("Receita", format_brl(metrics["revenue_cents"]))
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
                    st.checkbox("Aceite operacional", value=True, disabled=True)
                with marketing_column:
                    marketing = st.checkbox("Marketing opcional")
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
            "<div class='concept'><strong>Tamper experimental:</strong> sensor físico ainda não implementado.</div>",
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


def client_questions_page(store: DemoStore) -> None:
    banner(store)
    st.title("Decisões para a VRPlay")
    st.caption("Perguntas para validar na reunião · respostas serão registradas no documento oficial do projeto")
    left, right = st.columns(2, gap="large")
    groups = (left, right)
    for index, (group_title, questions) in enumerate(CLIENT_QUESTION_GROUPS):
        with groups[index % 2]:
            st.subheader(group_title)
            for number, title, question in questions:
                st.markdown(
                    '<div class="question-card">'
                    f'<span class="question-number">{escape(number)}</span>'
                    f'<span class="question-title">{escape(title)}</span>'
                    f'<div class="question-text">{escape(question)}</div>'
                    "</div>",
                    unsafe_allow_html=True,
                )


def control_page(store: DemoStore) -> None:
    def content(current_store: DemoStore, snapshot: dict) -> None:
        st.title("Controle da Demo")
        st.warning("Controles internos da apresentação.")
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
        render_timeline(snapshot, 12)

    render_shell(store, content)
