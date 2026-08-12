import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';

// ========================================
// CONTROLLER DEL DASHBOARD / LEADS
// ========================================

import getLeadsWithConversations
    from '@salesforce/apex/AdvisorDashboardController.getLeadsWithConversations';

import getTodayAppointments
    from '@salesforce/apex/AdvisorDashboardController.getTodayAppointments';

import takeLeadConversation
    from '@salesforce/apex/AdvisorDashboardController.takeConversation';


// ========================================
// CONTROLLER DE CONVERSACIONES / MENSAJES
// ========================================

import getConversations
    from '@salesforce/apex/ConversationController.getConversations';

import getMessages
    from '@salesforce/apex/ConversationController.getMessages';

import takeConversationRecord
    from '@salesforce/apex/ConversationController.takeConversation';


// ========================================
// ETIQUETAS DE ESTADO
// ========================================

const STATUS_LABELS = {
    online: 'En conversación',
    waiting: 'Esperando respuesta',
    attention: 'Requiere atención',
    advisor: 'Atendido por ti',
    offline: 'Sin conversación'
};


export default class AdvisorDashboard extends LightningElement {

    // ========================================
    // ESTADO GENERAL
    // ========================================

    searchTerm = '';
    selectedProspectId = null;
    activeSection = 'home';


    // ========================================
    // ESTADO DE CONVERSACIÓN / CHAT
    // ========================================

    selectedConversationId = null;
    chatMessages = [];
    isLoadingMessages = false;
    messagesError = null;


    // ========================================
    // DATOS DESDE APEX
    // ========================================

    @wire(getLeadsWithConversations)
    leadsWired;

    @wire(getTodayAppointments)
    appointmentsWired;

    @wire(getConversations)
    conversationsWired;


    // ========================================
    // NAVEGACIÓN
    // ========================================

    handleNavClick(event) {
        const section = event.currentTarget.dataset.section;

        if (section) {
            this.activeSection = section;
        }
    }


    get navClasses() {
        const base = 'nav-item';

        return {
            home:
                this.activeSection === 'home'
                    ? `${base} active`
                    : base,

            prospectos:
                this.activeSection === 'prospectos'
                    ? `${base} active`
                    : base,

            conversaciones:
                this.activeSection === 'conversaciones'
                    ? `${base} active`
                    : base,

            citas:
                this.activeSection === 'citas'
                    ? `${base} active`
                    : base,

            alertas:
                this.activeSection === 'alertas'
                    ? `${base} active`
                    : base,

            pipeline:
                this.activeSection === 'pipeline'
                    ? `${base} active`
                    : base,

            configuracion:
                this.activeSection === 'configuracion'
                    ? `${base} active`
                    : base
        };
    }


    get showProspectsPanel() {
        return [
            'home',
            'prospectos',
            'conversaciones'
        ].includes(this.activeSection);
    }


    get showPipelinePanel() {
        return [
            'home',
            'citas',
            'alertas',
            'pipeline'
        ].includes(this.activeSection);
    }


    get showAppointmentsPanel() {
        return [
            'home',
            'citas'
        ].includes(this.activeSection);
    }


    get showAlertsPanel() {
        return [
            'home',
            'alertas',
            'conversaciones'
        ].includes(this.activeSection);
    }


    get showProspectSummaryPanel() {
        return [
            'home',
            'prospectos',
            'alertas'
        ].includes(this.activeSection);
    }

    get showConversationsWorkspace() {
    return this.activeSection === 'conversaciones';
    }

    get showStandardDashboard() {
    return this.activeSection !== 'conversaciones';
    }

    get showIntegrationsPanel() {
        return [
            'home',
            'pipeline',
            'configuracion'
        ].includes(this.activeSection);
    }


    // ========================================
    // ESTADO DE CARGA Y ERROR
    // ========================================

    get isLoading() {
        return (
            !this.leadsWired ||
            this.leadsWired.loading ||

            !this.appointmentsWired ||
            this.appointmentsWired.loading ||

            !this.conversationsWired ||
            this.conversationsWired.loading
        );
    }


    get hasError() {
        return (
            (this.leadsWired && this.leadsWired.error) ||
            (this.appointmentsWired && this.appointmentsWired.error) ||
            (this.conversationsWired && this.conversationsWired.error)
        );
    }


    // ========================================
    // DATOS REACTIVOS
    // ========================================

    get rawLeads() {
        return this.leadsWired?.data ?? [];
    }


    get rawAppointments() {
        return this.appointmentsWired?.data ?? [];
    }


    get rawConversations() {
        return this.conversationsWired?.data ?? [];
    }


    get prospects() {
        return this.rawLeads.map(
            lead => this.decorateLead(lead)
        );
    }


    get appointments() {
        return this.rawAppointments.map(
            evt => this.decorateEvent(evt)
        );
    }


    // ========================================
    // MÉTRICAS
    // ========================================

    get onlineProspects() {
        return this.rawLeads.length;
    }


    get activeConversations() {
        return this.rawLeads.filter(
            lead => lead.En_Conversacion__c === true
        ).length;
    }


    get attentionCount() {
        return this.rawLeads.filter(
            lead => lead.Necesita_Atencion__c === true
        ).length;
    }


    get todayAppointments() {
        return this.rawAppointments.length;
    }


    // ========================================
    // PROSPECTOS
    // ========================================

    get filteredProspects() {

        const search = (this.searchTerm || '')
            .trim()
            .toLowerCase();

        let result = this.prospects;


        if (search) {

            result = result.filter(prospect => {

                const searchableText = [
                    prospect.name,
                    prospect.channel,
                    prospect.interest,
                    prospect.activity,
                    prospect.stage,
                    prospect.statusLabel
                ]
                    .join(' ')
                    .toLowerCase();

                return searchableText.includes(search);
            });
        }


        return result;
    }


    get filteredProspectCount() {
        return this.filteredProspects.length;
    }


    // ========================================
    // ALERTAS
    // ========================================

    get attentionProspects() {

        return this.rawLeads
            .filter(
                lead =>
                    lead.Necesita_Atencion__c === true
            )
            .map(
                lead =>
                    this.decorateLead(lead)
            );
    }


    // ========================================
    // PROSPECTO SELECCIONADO
    // ========================================

    get hasSelectedProspect() {

        return (
            Array.isArray(this.prospects) &&
            this.prospects.length > 0
        );
    }


    get selectedProspect() {

        const list = this.prospects;


        if (!list || !list.length) {

            return {
                id: '',
                name: '—',
                initials: '?',
                interest: '—',
                stage: '—',
                nextAppointment: '—',
                channel: '—',
                activity: '—',
                avatarLargeClass: 'summary-avatar',
                rowClass: '',
                avatarClass: '',
                statusClass: '',
                statusLabel: '—',
                alertReason: '',
                lastActivity: '',
                channelIcon: 'utility:chat',
                needsAttention: false,
                inConversation: false
            };
        }


        const prospect = list.find(
            item =>
                item.id === this.selectedProspectId
        );


        return prospect || list[0];
    }


    // ========================================
    // CONVERSACIÓN SELECCIONADA
    // ========================================

    get selectedConversation() {

        if (!this.selectedConversationId) {
            return null;
        }


        return (
            this.rawConversations.find(
                conversation =>
                    conversation.Id ===
                    this.selectedConversationId
            ) || null
        );
    }


    get hasSelectedConversation() {
        return Boolean(this.selectedConversationId);
    }



    get selectedConversationAdvisorName() {
        return this.selectedConversation?.Assigned_Advisor__r?.Name ?? 'Sin asignar';
    }


    get hasChatMessages() {
        return (
            Array.isArray(this.chatMessages) &&
            this.chatMessages.length > 0
        );
    }


    // ========================================
    // DECORACIÓN:
    // LEAD → FILA UI
    // ========================================

    decorateLead(lead) {

        const id = lead.Id;

        const firstName =
            lead.FirstName ?? '';

        const lastName =
            lead.LastName ?? '';

        const name =
            `${firstName} ${lastName}`.trim() ||
            '(Sin nombre)';

        const initials =
            `${firstName.charAt(0)}${lastName.charAt(0)}`
                .toUpperCase() ||
            '?';


        const needsAttention =
            lead.Necesita_Atencion__c === true;

        const inConversation =
            lead.En_Conversacion__c === true;


        const statusRaw =
            lead.Estado__c ?? 'offline';

        const status =
            STATUS_LABELS[statusRaw]
                ? statusRaw
                : 'offline';


        let rowClass =
            'prospect-row';

        if (needsAttention) {
            rowClass += ' attention-row';
        }



        if (id === this.selectedProspectId) {
            rowClass += ' selected-row';
        }


        let avatarClass =
            'prospect-avatar';

        if (needsAttention) {
            avatarClass += ' attention-avatar';
        }


        let statusClass =
            'status-pill';

        if (status === 'online') {
            statusClass += ' status-online';
        }

        if (status === 'waiting') {
            statusClass += ' status-waiting';
        }

        if (status === 'attention') {
            statusClass += ' status-attention';
        }

        if (status === 'advisor') {
            statusClass += ' status-advisor';
        }


        const channel =
            lead.Canal__c ?? '—';

        const channelIcon =
            channel === 'Correo'
                ? 'utility:email'
                : 'utility:chat';


        const interest =
            lead.Producto_de_Interes__c ?? '—';

        const stage =
            lead.Etapa__c ?? '—';

        const activity =
            lead.Actividad_Actual__c ?? '—';

        const lastActivity =
            this.formatRelative(
                lead.Ultima_Actividad__c
            );


        const nextEvent =
            (
                lead.Events &&
                lead.Events.length > 0
            )
                ? lead.Events[0]
                : null;


        const nextAppointment =
            nextEvent
                ? this.formatTime(
                    nextEvent.StartDateTime
                )
                : 'Sin cita';


        return {
            id,
            name,
            initials,

            channel,
            channelIcon,

            interest,
            stage,

            status,

            statusLabel:
                STATUS_LABELS[status] ?? status,

            activity,
            lastActivity,

            nextAppointment,

            needsAttention,
            inConversation,

            alertReason:
                lead.Razon_Alerta__c ?? '',

            rowClass,
            avatarClass,

            avatarLargeClass:
                needsAttention
                    ? 'summary-avatar attention-avatar'
                    : 'summary-avatar',

            statusClass
        };
    }


    // ========================================
    // DECORACIÓN:
    // EVENT → CITA UI
    // ========================================

    decorateEvent(evt) {

        const channel = 'WhatsApp';

        const channelClass =
            `channel-pill ${
                channel === 'Correo'
                    ? 'email'
                    : 'whatsapp'
            }`;


        return {
            id: evt.Id,

            name:
                evt.WhoName ||
                evt.Subject ||
                '—',

            date:
                this.formatDateTime(
                    evt.StartDateTime
                ),

            channel,

            channelClass
        };
    }


    // ========================================
    // DECORACIÓN:
    // MESSAGE → BURBUJA DE CHAT
    // ========================================

    decorateMessage(message) {

        const incoming =
            message.Direction__c === 'Incoming';


        return {
            id: message.Id,

            number:
                message.Name,

            body:
                message.Body__c ?? '',

            direction:
                message.Direction__c,

            senderType:
                message.Sender_Type__c ?? '',

            status:
                message.Status__c ?? '',

            channel:
                message.Channel__c ?? '',

            sentAt:
                this.formatDateTime(
                    message.Sent_At__c ||
                    message.CreatedDate
                ),

            senderAdvisor:
                message.Sender_Advisor__r?.Name ?? '',

            incoming,

            outgoing:
                !incoming,

            bubbleClass:
                incoming
                    ? 'chat-message incoming'
                    : 'chat-message outgoing'
        };
    }


    // ========================================
    // RELACIÓN:
    // LEAD → CONVERSATION__C
    // ========================================

    findConversationForLead(leadId) {

        if (!leadId) {
            return null;
        }


        return (
            this.rawConversations.find(
                conversation =>
                    conversation.Lead__c === leadId
            ) ||
            null
        );
    }


    // ========================================
    // CARGAR MENSAJES
    // ========================================

    async loadMessagesForLead(leadId) {

        const conversation =
            this.findConversationForLead(leadId);


        if (!conversation) {

            this.selectedConversationId = null;

            this.chatMessages = [];

            this.messagesError = null;

            return;
        }


        this.selectedConversationId =
            conversation.Id;

        this.isLoadingMessages = true;

        this.messagesError = null;


        try {

            const messages =
                await getMessages({
                    conversationId:
                        conversation.Id
                });


            this.chatMessages =
                (messages || []).map(
                    message =>
                        this.decorateMessage(
                            message
                        )
                );

        } catch (error) {

            console.error(
                'Error cargando mensajes:',
                error
            );

            this.chatMessages = [];

            this.messagesError = error;

        } finally {

            this.isLoadingMessages = false;
        }
    }


    // ========================================
    // FORMATO DE FECHAS
    // ========================================

    formatDateTime(dtString) {

        if (!dtString) {
            return '';
        }


        const dt =
            new Date(dtString);

        const now =
            new Date();


        const isToday =
            dt.toDateString() ===
            now.toDateString();


        const time =
            dt.toLocaleTimeString(
                'es-MX',
                {
                    hour: 'numeric',
                    minute: '2-digit'
                }
            );


        return isToday
            ? `Hoy, ${time}`
            : `${dt.toLocaleDateString('es-MX')}, ${time}`;
    }


    formatTime(dtString) {

        if (!dtString) {
            return '';
        }


        const dt =
            new Date(dtString);

        const now =
            new Date();


        const isToday =
            dt.toDateString() ===
            now.toDateString();


        const time =
            dt.toLocaleTimeString(
                'es-MX',
                {
                    hour: 'numeric',
                    minute: '2-digit'
                }
            );


        if (isToday) {
            return `Hoy, ${time}`;
        }


        const tomorrow =
            new Date(now);

        tomorrow.setDate(
            tomorrow.getDate() + 1
        );


        if (
            dt.toDateString() ===
            tomorrow.toDateString()
        ) {
            return `Mañana, ${time}`;
        }


        return `${dt.toLocaleDateString('es-MX')}, ${time}`;
    }


    formatRelative(dtString) {

        if (!dtString) {
            return '—';
        }


        const dt =
            new Date(dtString);


        const diffMs =
            Date.now() -
            dt.getTime();


        const diffMin =
            Math.round(
                diffMs / 60000
            );


        if (diffMin < 1) {
            return 'Ahora';
        }


        if (diffMin < 60) {
            return `Hace ${diffMin} min`;
        }


        const diffH =
            Math.round(
                diffMin / 60
            );


        if (diffH < 24) {
            return `Hace ${diffH} h`;
        }


        const diffD =
            Math.round(
                diffH / 24
            );


        if (diffD < 7) {
            return `Hace ${diffD} d`;
        }


        return dt.toLocaleDateString(
            'es-MX'
        );
    }


    // ========================================
    // BÚSQUEDA
    // ========================================

    handleSearch(event) {
        this.searchTerm =
            event.target.value;
    }


    // ========================================
    // SELECCIONAR PROSPECTO
    // + CARGAR SU CONVERSACIÓN
    // ========================================

    async handleSelectProspect(event) {

        const prospectId =
            event.currentTarget.dataset.id;


        if (!prospectId) {
            return;
        }


        this.selectedProspectId =
            prospectId;


        await this.loadMessagesForLead(
            prospectId
        );
    }


    // ========================================
    // TOMAR CONVERSACIÓN
    // ========================================

    async handleTakeConversation(event) {

        const leadId =
            event.currentTarget.dataset.id;


        if (!leadId) {
            return;
        }


        this.selectedProspectId =
            leadId;


        const conversation =
            this.findConversationForLead(
                leadId
            );


        try {

            // =================================
            // SI EXISTE CONVERSATION__C
            // =================================

            if (conversation) {

                await takeConversationRecord({
                    conversationId:
                        conversation.Id
                });


                this.selectedConversationId =
                    conversation.Id;


                await Promise.all([
                    refreshApex(
                        this.leadsWired
                    ),

                    refreshApex(
                        this.conversationsWired
                    )
                ]);


                await this.loadMessagesForLead(
                    leadId
                );


            } else {

                // =================================
                // FALLBACK:
                // LEADS SIN CONVERSATION__C
                // =================================

                await takeLeadConversation({
                    leadId
                });


                await refreshApex(
                    this.leadsWired
                );
            }


        } catch (err) {

            console.error(
                'Error tomando conversación:',
                err
            );
        }
    }
}